//! Experimental lazy workspace mount support backed by a local WebDAV server.

use crate::cli::MountServeCommand;
use crate::config::ensure_state_dir;
use crate::error::{MicError, Result};
use crate::grpc::hif_v1::{call_optional_auth, pb, repository_ref};
use crate::grpc::{Endpoint, GrpcClient};
use crate::workspace::{WorkspaceEntry, WorkspaceManifest, HIF_DIR, MANIFEST_FILE};
use bytes::Bytes;
use dav_server::davpath::DavPath;
use dav_server::fakels::FakeLs;
use dav_server::fs::{
    DavDirEntry, DavFile, DavFileSystem, DavMetaData, FsError, FsFuture, FsResult, FsStream,
    OpenOptions, ReadDirMeta,
};
use dav_server::DavHandler;
use futures_util::future::{self, FutureExt};
use futures_util::stream;
use http::Request;
use hyper::body::Incoming;
use hyper::server::conn::http1;
use hyper::service::service_fn;
use hyper_util::rt::TokioIo;
use serde::{Deserialize, Serialize};
use std::collections::{BTreeSet, HashSet};
use std::convert::Infallible;
#[cfg(target_os = "linux")]
use std::env;
use std::ffi::OsString;
use std::fs;
use std::io::{Read, Seek, SeekFrom, Write};
use std::net::SocketAddr;
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};
use std::sync::Arc;
use std::time::{Duration, SystemTime};
use tokio::net::TcpListener;

const MOUNTS_DIR: &str = "mounts";
const MOUNT_INFO_FILE: &str = "mount.json";
const READY_FILE: &str = "ready.json";
const TOMBSTONES_FILE: &str = "tombstones.json";

#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq, Default)]
#[serde(rename_all = "snake_case")]
pub enum MountKind {
    #[default]
    Direct,
    LinuxGioLink,
    WindowsDriveLink,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct LazyMountInfo {
    pub version: u32,
    pub server: String,
    pub account: String,
    pub repository: String,
    pub mount_path: String,
    pub state_dir: String,
    pub port: u16,
    pub revision_hash: String,
    pub server_pid: Option<u32>,
    #[serde(default)]
    pub mount_kind: MountKind,
    #[serde(default)]
    pub mount_source: Option<String>,
    #[serde(default)]
    pub link_target: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct LazyMountReady {
    pub pid: u32,
    pub port: u16,
}

#[derive(Debug, Clone)]
pub struct LazyMountState {
    pub info: LazyMountInfo,
}

impl LazyMountState {
    pub fn state_dir(&self) -> PathBuf {
        PathBuf::from(&self.info.state_dir)
    }

    pub fn workspace_root(&self) -> PathBuf {
        self.state_dir().join("workspace")
    }

    pub fn workspace_hif_root(&self) -> PathBuf {
        self.workspace_root().join(HIF_DIR)
    }

    pub fn manifest_path(&self) -> PathBuf {
        self.workspace_hif_root().join(MANIFEST_FILE)
    }

    pub fn mount_info_path(&self) -> PathBuf {
        self.workspace_hif_root().join(MOUNT_INFO_FILE)
    }

    pub fn state_info_path(&self) -> PathBuf {
        self.state_dir().join(MOUNT_INFO_FILE)
    }

    pub fn ready_path(&self) -> PathBuf {
        self.state_dir().join(READY_FILE)
    }

    pub fn overlay_root(&self) -> PathBuf {
        self.state_dir().join("overlay")
    }

    pub fn cache_root(&self) -> PathBuf {
        self.state_dir().join("cache")
    }

    pub fn tombstones_path(&self) -> PathBuf {
        self.state_dir().join(TOMBSTONES_FILE)
    }

    pub fn revision_hash_bytes(&self) -> Vec<u8> {
        decode_hex(&self.info.revision_hash).unwrap_or_default()
    }
}

#[derive(Debug, Clone)]
pub struct RemoteTree {
    pub entries: Vec<WorkspaceEntry>,
    pub revision_hash: Vec<u8>,
}

#[derive(Debug, Clone)]
pub struct MountActivation {
    pub kind: MountKind,
    pub mount_source: Option<String>,
    pub link_target: Option<String>,
}

#[derive(Clone)]
pub struct LazyMountFs {
    state: Arc<LazyMountState>,
}

impl LazyMountFs {
    pub fn new(state: LazyMountState) -> Self {
        Self {
            state: Arc::new(state),
        }
    }

    fn workspace_meta_path(&self, relative: &str) -> PathBuf {
        self.state.workspace_root().join(relative)
    }

    fn overlay_path(&self, relative: &str) -> PathBuf {
        self.state.overlay_root().join(relative)
    }

    fn cache_path_for_hash(&self, hash: &str) -> PathBuf {
        let prefix = hash.get(0..2).unwrap_or("__");
        self.state
            .cache_root()
            .join(prefix)
            .join(format!("{hash}.blob"))
    }

    fn load_manifest(&self) -> FsResult<WorkspaceManifest> {
        WorkspaceManifest::load_from(&self.state.manifest_path())
            .map_err(fs_error_from_mic)?
            .ok_or(FsError::NotFound)
    }

    fn save_manifest(&self, manifest: &WorkspaceManifest) -> FsResult<()> {
        manifest
            .save_to(&self.state.manifest_path())
            .map_err(fs_error_from_mic)
    }

    fn load_tombstones(&self) -> FsResult<HashSet<String>> {
        let path = self.state.tombstones_path();
        if !path.exists() {
            return Ok(HashSet::new());
        }

        let data = fs::read_to_string(path).map_err(FsError::from)?;
        let entries: Vec<String> =
            serde_json::from_str(&data).map_err(|_| FsError::GeneralFailure)?;
        Ok(entries.into_iter().collect())
    }

    fn save_tombstones(&self, tombstones: &HashSet<String>) -> FsResult<()> {
        let mut entries = tombstones.iter().cloned().collect::<Vec<_>>();
        entries.sort();
        let data = serde_json::to_string_pretty(&entries).map_err(|_| FsError::GeneralFailure)?;
        fs::write(self.state.tombstones_path(), data).map_err(FsError::from)
    }

    fn is_meta_path(relative: &str) -> bool {
        relative == HIF_DIR || relative.starts_with(".hif/")
    }

    fn relative_path(path: &DavPath) -> FsResult<String> {
        let rendered = path.as_pathbuf().to_string_lossy().replace('\\', "/");
        let trimmed = rendered
            .trim_start_matches('/')
            .trim_end_matches('/')
            .to_string();
        if trimmed.is_empty() {
            return Ok(String::new());
        }
        if !crate::workspace::is_safe_path(&trimmed) {
            return Err(FsError::Forbidden);
        }
        Ok(trimmed)
    }

    fn is_tombstoned(tombstones: &HashSet<String>, relative: &str) -> bool {
        tombstones.iter().any(|entry| {
            entry == relative || (!entry.is_empty() && relative.starts_with(&(entry.clone() + "/")))
        })
    }

    fn base_file_entry<'a>(
        manifest: &'a WorkspaceManifest,
        tombstones: &HashSet<String>,
        relative: &str,
    ) -> Option<&'a WorkspaceEntry> {
        if Self::is_tombstoned(tombstones, relative) {
            return None;
        }
        manifest.entries.iter().find(|entry| entry.path == relative)
    }

    fn base_dir_exists(
        manifest: &WorkspaceManifest,
        tombstones: &HashSet<String>,
        relative: &str,
    ) -> bool {
        let prefix = if relative.is_empty() {
            String::new()
        } else {
            format!("{relative}/")
        };

        manifest.entries.iter().any(|entry| {
            !Self::is_tombstoned(tombstones, &entry.path)
                && entry.path.starts_with(&prefix)
                && entry.path != relative
        })
    }

    fn basic_dir_meta() -> Box<dyn DavMetaData> {
        Box::new(BasicMetaData {
            is_dir: true,
            len: 0,
            modified: SystemTime::now(),
        })
    }

    fn basic_file_meta(len: u64) -> Box<dyn DavMetaData> {
        Box::new(BasicMetaData {
            is_dir: false,
            len,
            modified: SystemTime::now(),
        })
    }

    fn local_metadata(path: &Path) -> FsResult<Box<dyn DavMetaData>> {
        let metadata = fs::metadata(path).map_err(FsError::from)?;
        Ok(Box::new(BasicMetaData {
            is_dir: metadata.is_dir(),
            len: metadata.len(),
            modified: metadata.modified().unwrap_or_else(|_| SystemTime::now()),
        }))
    }

    fn ensure_overlay_parent(&self, relative: &str) -> FsResult<()> {
        if let Some(parent) = self.overlay_path(relative).parent() {
            fs::create_dir_all(parent).map_err(FsError::from)?;
        }
        Ok(())
    }

    fn clear_tombstones_for(&self, relative: &str) -> FsResult<()> {
        let mut tombstones = self.load_tombstones()?;
        if relative.is_empty() {
            return Ok(());
        }
        let mut changed = false;
        let mut current = Some(relative.to_string());
        while let Some(path) = current {
            if tombstones.remove(&path) {
                changed = true;
            }
            current = Path::new(&path)
                .parent()
                .map(|parent| parent.to_string_lossy().replace('\\', "/"))
                .filter(|parent| !parent.is_empty());
        }
        if changed {
            self.save_tombstones(&tombstones)?;
        }
        Ok(())
    }

    fn add_tombstone(&self, relative: &str) -> FsResult<()> {
        let mut tombstones = self.load_tombstones()?;
        tombstones.insert(relative.to_string());
        self.save_tombstones(&tombstones)
    }

    async fn hydrate_base_file(&self, relative: &str, entry: &WorkspaceEntry) -> FsResult<PathBuf> {
        let cache_path = self.cache_path_for_hash(&entry.hash);
        if cache_path.exists() {
            return Ok(cache_path);
        }

        if let Some(parent) = cache_path.parent() {
            fs::create_dir_all(parent).map_err(FsError::from)?;
        }

        let endpoint = Endpoint::parse(&self.state.info.server).map_err(fs_error_from_mic)?;
        let client = GrpcClient::new(endpoint);
        let response: pb::PathResponse = call_optional_auth(
            &client,
            "/hif.v1.ContentService/GetPath",
            &pb::GetPathRequest {
                repository: Some(repository_ref(
                    &self.state.info.account,
                    &self.state.info.repository,
                )),
                revision_hash: self.state.revision_hash_bytes(),
                path: relative.to_string(),
            },
        )
        .await
        .map_err(fs_error_from_mic)?;

        let tmp_path = cache_path.with_extension("tmp");
        fs::write(&tmp_path, &response.content).map_err(FsError::from)?;
        fs::rename(&tmp_path, &cache_path).map_err(FsError::from)?;

        let mut manifest = self.load_manifest()?;
        if let Some(existing) = manifest
            .entries
            .iter_mut()
            .find(|item| item.path == relative)
        {
            existing.size = response.size;
            existing.mode = response.mode;
            let _ = self.save_manifest(&manifest);
        }

        Ok(cache_path)
    }

    async fn copy_up_base_file(&self, relative: &str, entry: &WorkspaceEntry) -> FsResult<PathBuf> {
        let cache_path = self.hydrate_base_file(relative, entry).await?;
        self.ensure_overlay_parent(relative)?;
        let overlay_path = self.overlay_path(relative);
        if !overlay_path.exists() {
            fs::copy(cache_path, &overlay_path).map_err(FsError::from)?;
        }
        Ok(overlay_path)
    }

    fn overlay_children(&self, relative: &str) -> FsResult<Vec<SimpleDirEntry>> {
        let dir = self.overlay_path(relative);
        if !dir.exists() || !dir.is_dir() {
            return Ok(Vec::new());
        }

        let mut entries = Vec::new();
        for entry in fs::read_dir(dir).map_err(FsError::from)? {
            let entry = entry.map_err(FsError::from)?;
            let metadata = entry.metadata().map_err(FsError::from)?;
            entries.push(SimpleDirEntry {
                name: entry
                    .file_name()
                    .to_string_lossy()
                    .into_owned()
                    .into_bytes(),
                meta: BasicMetaData {
                    is_dir: metadata.is_dir(),
                    len: metadata.len(),
                    modified: metadata.modified().unwrap_or_else(|_| SystemTime::now()),
                },
            });
        }

        Ok(entries)
    }

    fn read_dir_entries(&self, relative: &str) -> FsResult<Vec<SimpleDirEntry>> {
        if Self::is_meta_path(relative) {
            let local = self.workspace_meta_path(relative);
            if !local.exists() || !local.is_dir() {
                return Err(FsError::NotFound);
            }
            let mut entries = Vec::new();
            for entry in fs::read_dir(local).map_err(FsError::from)? {
                let entry = entry.map_err(FsError::from)?;
                let metadata = entry.metadata().map_err(FsError::from)?;
                entries.push(SimpleDirEntry {
                    name: entry
                        .file_name()
                        .to_string_lossy()
                        .into_owned()
                        .into_bytes(),
                    meta: BasicMetaData {
                        is_dir: metadata.is_dir(),
                        len: metadata.len(),
                        modified: metadata.modified().unwrap_or_else(|_| SystemTime::now()),
                    },
                });
            }
            return Ok(entries);
        }

        let manifest = self.load_manifest()?;
        let tombstones = self.load_tombstones()?;
        let mut names = BTreeSet::new();
        let mut entries = Vec::new();

        if relative.is_empty() {
            names.insert(HIF_DIR.to_string());
            entries.push(SimpleDirEntry {
                name: HIF_DIR.as_bytes().to_vec(),
                meta: BasicMetaData {
                    is_dir: true,
                    len: 0,
                    modified: SystemTime::now(),
                },
            });
        }

        let prefix = if relative.is_empty() {
            String::new()
        } else {
            format!("{relative}/")
        };

        for entry in &manifest.entries {
            if Self::is_tombstoned(&tombstones, &entry.path) || !entry.path.starts_with(&prefix) {
                continue;
            }

            let remainder = &entry.path[prefix.len()..];
            if remainder.is_empty() {
                continue;
            }

            let (name, is_dir) = match remainder.split_once('/') {
                Some((name, _)) => (name.to_string(), true),
                None => (remainder.to_string(), false),
            };

            if names.insert(name.clone()) {
                entries.push(SimpleDirEntry {
                    name: name.clone().into_bytes(),
                    meta: BasicMetaData {
                        is_dir,
                        len: if is_dir { 0 } else { entry.size },
                        modified: SystemTime::now(),
                    },
                });
            }
        }

        for entry in self.overlay_children(relative)? {
            let name = String::from_utf8_lossy(&entry.name).into_owned();
            if names.insert(name) {
                entries.push(entry);
            }
        }

        Ok(entries)
    }

    fn node_metadata(&self, relative: &str) -> FsResult<Box<dyn DavMetaData>> {
        if relative.is_empty() {
            return Ok(Self::basic_dir_meta());
        }

        if Self::is_meta_path(relative) {
            let local = self.workspace_meta_path(relative);
            return Self::local_metadata(&local);
        }

        let overlay = self.overlay_path(relative);
        if overlay.exists() {
            return Self::local_metadata(&overlay);
        }

        let manifest = self.load_manifest()?;
        let tombstones = self.load_tombstones()?;

        if let Some(entry) = Self::base_file_entry(&manifest, &tombstones, relative) {
            let cache_path = self.cache_path_for_hash(&entry.hash);
            if cache_path.exists() {
                return Self::local_metadata(&cache_path);
            }
            return Ok(Self::basic_file_meta(entry.size));
        }

        if Self::base_dir_exists(&manifest, &tombstones, relative) {
            return Ok(Self::basic_dir_meta());
        }

        Err(FsError::NotFound)
    }
}

impl DavFileSystem for LazyMountFs {
    fn open<'a>(
        &'a self,
        path: &'a DavPath,
        options: OpenOptions,
    ) -> FsFuture<'a, Box<dyn DavFile>> {
        async move {
            let relative = Self::relative_path(path)?;

            if relative.is_empty() {
                return Err(FsError::Forbidden);
            }

            if Self::is_meta_path(&relative) {
                let local = self.workspace_meta_path(&relative);
                if let Some(parent) = local.parent() {
                    fs::create_dir_all(parent).map_err(FsError::from)?;
                }
                return open_local_file(local, &options).await;
            }

            if options.write
                || options.append
                || options.create
                || options.create_new
                || options.truncate
            {
                self.clear_tombstones_for(&relative)?;
                self.ensure_overlay_parent(&relative)?;

                let overlay_path = self.overlay_path(&relative);
                if !overlay_path.exists() && !options.create_new {
                    let manifest = self.load_manifest()?;
                    let tombstones = self.load_tombstones()?;
                    if let Some(entry) = Self::base_file_entry(&manifest, &tombstones, &relative) {
                        let _ = self.copy_up_base_file(&relative, entry).await?;
                    }
                }

                return open_local_file(overlay_path, &options).await;
            }

            let overlay_path = self.overlay_path(&relative);
            if overlay_path.exists() {
                return open_local_file(overlay_path, &options).await;
            }

            let manifest = self.load_manifest()?;
            let tombstones = self.load_tombstones()?;
            let entry = Self::base_file_entry(&manifest, &tombstones, &relative)
                .ok_or(FsError::NotFound)?
                .clone();
            let local = self.hydrate_base_file(&relative, &entry).await?;
            open_local_file(local, &options).await
        }
        .boxed()
    }

    fn read_dir<'a>(
        &'a self,
        path: &'a DavPath,
        _meta: ReadDirMeta,
    ) -> FsFuture<'a, FsStream<Box<dyn DavDirEntry>>> {
        async move {
            let relative = Self::relative_path(path)?;
            let entries = self
                .read_dir_entries(&relative)?
                .into_iter()
                .map(|entry| Ok::<Box<dyn DavDirEntry>, FsError>(Box::new(entry)))
                .collect::<Vec<_>>();
            let stream: FsStream<Box<dyn DavDirEntry>> = Box::pin(stream::iter(entries));
            Ok(stream)
        }
        .boxed()
    }

    fn metadata<'a>(&'a self, path: &'a DavPath) -> FsFuture<'a, Box<dyn DavMetaData>> {
        async move {
            let relative = Self::relative_path(path)?;
            self.node_metadata(&relative)
        }
        .boxed()
    }

    fn create_dir<'a>(&'a self, path: &'a DavPath) -> FsFuture<'a, ()> {
        async move {
            let relative = Self::relative_path(path)?;
            if relative.is_empty() {
                return Ok(());
            }

            if Self::is_meta_path(&relative) {
                fs::create_dir_all(self.workspace_meta_path(&relative)).map_err(FsError::from)?;
                return Ok(());
            }

            self.clear_tombstones_for(&relative)?;
            fs::create_dir_all(self.overlay_path(&relative)).map_err(FsError::from)?;
            Ok(())
        }
        .boxed()
    }

    fn remove_dir<'a>(&'a self, path: &'a DavPath) -> FsFuture<'a, ()> {
        async move {
            let relative = Self::relative_path(path)?;
            if relative.is_empty() || Self::is_meta_path(&relative) {
                return Err(FsError::Forbidden);
            }

            let overlay = self.overlay_path(&relative);
            if overlay.exists() {
                fs::remove_dir_all(&overlay).map_err(FsError::from)?;
            }

            let manifest = self.load_manifest()?;
            let tombstones = self.load_tombstones()?;
            if Self::base_dir_exists(&manifest, &tombstones, &relative) {
                self.add_tombstone(&relative)?;
            }

            Ok(())
        }
        .boxed()
    }

    fn remove_file<'a>(&'a self, path: &'a DavPath) -> FsFuture<'a, ()> {
        async move {
            let relative = Self::relative_path(path)?;
            if Self::is_meta_path(&relative) {
                let local = self.workspace_meta_path(&relative);
                if local.exists() {
                    fs::remove_file(local).map_err(FsError::from)?;
                }
                return Ok(());
            }

            let overlay = self.overlay_path(&relative);
            if overlay.exists() {
                fs::remove_file(&overlay).map_err(FsError::from)?;
            }

            let manifest = self.load_manifest()?;
            let tombstones = self.load_tombstones()?;
            if Self::base_file_entry(&manifest, &tombstones, &relative).is_some() {
                self.add_tombstone(&relative)?;
            }

            Ok(())
        }
        .boxed()
    }

    fn rename<'a>(&'a self, from: &'a DavPath, to: &'a DavPath) -> FsFuture<'a, ()> {
        async move {
            let from_relative = Self::relative_path(from)?;
            let to_relative = Self::relative_path(to)?;

            if from_relative.is_empty() || to_relative.is_empty() {
                return Err(FsError::Forbidden);
            }

            if Self::is_meta_path(&from_relative) || Self::is_meta_path(&to_relative) {
                let from_local = self.workspace_meta_path(&from_relative);
                let to_local = self.workspace_meta_path(&to_relative);
                if let Some(parent) = to_local.parent() {
                    fs::create_dir_all(parent).map_err(FsError::from)?;
                }
                fs::rename(from_local, to_local).map_err(FsError::from)?;
                return Ok(());
            }

            let from_overlay = self.overlay_path(&from_relative);
            if !from_overlay.exists() {
                let manifest = self.load_manifest()?;
                let tombstones = self.load_tombstones()?;
                let entry = Self::base_file_entry(&manifest, &tombstones, &from_relative)
                    .ok_or(FsError::NotFound)?
                    .clone();
                let _ = self.copy_up_base_file(&from_relative, &entry).await?;
            }

            self.clear_tombstones_for(&to_relative)?;
            if let Some(parent) = self.overlay_path(&to_relative).parent() {
                fs::create_dir_all(parent).map_err(FsError::from)?;
            }
            fs::rename(
                self.overlay_path(&from_relative),
                self.overlay_path(&to_relative),
            )
            .map_err(FsError::from)?;

            let manifest = self.load_manifest()?;
            let tombstones = self.load_tombstones()?;
            if Self::base_file_entry(&manifest, &tombstones, &from_relative).is_some()
                || Self::base_dir_exists(&manifest, &tombstones, &from_relative)
            {
                self.add_tombstone(&from_relative)?;
            }

            Ok(())
        }
        .boxed()
    }
}

#[derive(Debug)]
struct LocalDavFile {
    file: fs::File,
    path: PathBuf,
}

impl DavFile for LocalDavFile {
    fn metadata(&'_ mut self) -> FsFuture<'_, Box<dyn DavMetaData>> {
        async move { LazyMountFs::local_metadata(&self.path) }.boxed()
    }

    fn write_buf(&'_ mut self, mut buf: Box<dyn bytes::Buf + Send>) -> FsFuture<'_, ()> {
        async move {
            let bytes = buf.copy_to_bytes(buf.remaining());
            self.file.write_all(&bytes).map_err(FsError::from)
        }
        .boxed()
    }

    fn write_bytes(&'_ mut self, buf: Bytes) -> FsFuture<'_, ()> {
        async move { self.file.write_all(&buf).map_err(FsError::from) }.boxed()
    }

    fn read_bytes(&'_ mut self, count: usize) -> FsFuture<'_, Bytes> {
        async move {
            let mut buf = vec![0; count];
            let read = self.file.read(&mut buf).map_err(FsError::from)?;
            buf.truncate(read);
            Ok(Bytes::from(buf))
        }
        .boxed()
    }

    fn seek(&'_ mut self, pos: SeekFrom) -> FsFuture<'_, u64> {
        async move { self.file.seek(pos).map_err(FsError::from) }.boxed()
    }

    fn flush(&'_ mut self) -> FsFuture<'_, ()> {
        async move {
            self.file.flush().map_err(FsError::from)?;
            self.file.sync_all().map_err(FsError::from)
        }
        .boxed()
    }
}

#[derive(Debug, Clone)]
struct BasicMetaData {
    is_dir: bool,
    len: u64,
    modified: SystemTime,
}

impl DavMetaData for BasicMetaData {
    fn len(&self) -> u64 {
        self.len
    }

    fn modified(&self) -> FsResult<SystemTime> {
        Ok(self.modified)
    }

    fn is_dir(&self) -> bool {
        self.is_dir
    }
}

#[derive(Debug)]
struct SimpleDirEntry {
    name: Vec<u8>,
    meta: BasicMetaData,
}

impl DavDirEntry for SimpleDirEntry {
    fn name(&self) -> Vec<u8> {
        self.name.clone()
    }

    fn metadata(&'_ self) -> FsFuture<'_, Box<dyn DavMetaData>> {
        future::ready(Ok(Box::new(self.meta.clone()) as Box<dyn DavMetaData>)).boxed()
    }

    fn is_dir(&'_ self) -> FsFuture<'_, bool> {
        future::ready(Ok(self.meta.is_dir)).boxed()
    }
}

async fn open_local_file(path: PathBuf, options: &OpenOptions) -> FsResult<Box<dyn DavFile>> {
    if let Some(parent) = path.parent() {
        fs::create_dir_all(parent).map_err(FsError::from)?;
    }

    let mut file_options = fs::OpenOptions::new();
    file_options
        .read(options.read || (!options.write && !options.append))
        .write(options.write || options.append)
        .append(options.append)
        .truncate(options.truncate)
        .create(options.create || options.write || options.append)
        .create_new(options.create_new);

    let file = file_options.open(&path).map_err(FsError::from)?;
    Ok(Box::new(LocalDavFile { file, path }))
}

fn decode_hex(value: &str) -> Option<Vec<u8>> {
    if value.len() % 2 != 0 {
        return None;
    }
    let mut bytes = Vec::with_capacity(value.len() / 2);
    for index in (0..value.len()).step_by(2) {
        bytes.push(u8::from_str_radix(&value[index..index + 2], 16).ok()?);
    }
    Some(bytes)
}

fn fs_error_from_mic(error: MicError) -> FsError {
    match error {
        MicError::NotAuthenticated
        | MicError::TokenExpired
        | MicError::InvalidTokens
        | MicError::NoDefaultServer
        | MicError::NoGrpcUrl
        | MicError::NoWebUrl
        | MicError::DiscoveryFailed(_)
        | MicError::InvalidServer(_)
        | MicError::ConfigError(_)
        | MicError::GrpcError(_)
        | MicError::HttpError(_)
        | MicError::Reqwest(_) => FsError::GeneralFailure,
        MicError::Io(error) => FsError::from(error),
        _ => FsError::GeneralFailure,
    }
}

pub async fn fetch_remote_tree(
    client: &GrpcClient,
    account: &str,
    repository: &str,
) -> Result<RemoteTree> {
    let repository_ref = repository_ref(account, repository);
    let head: pb::RepositoryHeadResponse = call_optional_auth(
        client,
        "/hif.v1.VersioningService/GetRepositoryHead",
        &pb::GetRepositoryHeadRequest {
            repository: Some(repository_ref.clone()),
        },
    )
    .await?;

    let revision_hash = head
        .head
        .as_ref()
        .map(|value| value.hash.clone())
        .unwrap_or_default();

    let tree: pb::TreeResponse = call_optional_auth(
        client,
        "/hif.v1.ContentService/GetTree",
        &pb::GetTreeRequest {
            repository: Some(repository_ref),
            revision_hash: revision_hash.clone(),
        },
    )
    .await?;

    Ok(RemoteTree {
        entries: tree
            .entries
            .into_iter()
            .map(|entry| WorkspaceEntry {
                path: entry.path,
                hash: entry.hash,
                mode: 0,
                size: 0,
            })
            .collect(),
        revision_hash,
    })
}

pub fn create_state_dir() -> Result<PathBuf> {
    let root = ensure_state_dir()?
        .join(MOUNTS_DIR)
        .join(uuid::Uuid::now_v7().to_string());
    fs::create_dir_all(&root)
        .map_err(|error| MicError::Other(format!("Failed to create mount state dir: {}", error)))?;
    Ok(root)
}

pub fn persist_mount_state(
    state_dir: &Path,
    server: &str,
    account: &str,
    repository: &str,
    mount_path: &Path,
    port: u16,
    tree: &RemoteTree,
) -> Result<LazyMountInfo> {
    fs::create_dir_all(state_dir.join("workspace").join(HIF_DIR))?;
    fs::create_dir_all(state_dir.join("overlay"))?;
    fs::create_dir_all(state_dir.join("cache"))?;

    let mut manifest = WorkspaceManifest::new(server, account, repository);
    manifest.tree_hash = encode_hex(&tree.revision_hash);
    manifest.entries = tree.entries.clone();
    manifest.save_to(
        &state_dir
            .join("workspace")
            .join(HIF_DIR)
            .join(MANIFEST_FILE),
    )?;

    let info = LazyMountInfo {
        version: 1,
        server: server.to_string(),
        account: account.to_string(),
        repository: repository.to_string(),
        mount_path: mount_path.display().to_string(),
        state_dir: state_dir.display().to_string(),
        port,
        revision_hash: encode_hex(&tree.revision_hash),
        server_pid: None,
        mount_kind: MountKind::Direct,
        mount_source: None,
        link_target: None,
    };

    persist_mount_info(state_dir, &info)?;
    fs::write(state_dir.join(TOMBSTONES_FILE), "[]")?;
    Ok(info)
}

pub fn load_mount_info(state_dir: &Path) -> Result<LazyMountInfo> {
    let data = fs::read_to_string(state_dir.join(MOUNT_INFO_FILE))?;
    serde_json::from_str(&data)
        .map_err(|error| MicError::ConfigError(format!("failed to parse mount info: {}", error)))
}

pub fn persist_mount_info(state_dir: &Path, info: &LazyMountInfo) -> Result<()> {
    let data = serde_json::to_string_pretty(info).map_err(|error| {
        MicError::ConfigError(format!("failed to serialize mount info: {}", error))
    })?;
    fs::write(state_dir.join(MOUNT_INFO_FILE), &data)?;
    fs::write(
        state_dir
            .join("workspace")
            .join(HIF_DIR)
            .join(MOUNT_INFO_FILE),
        data,
    )?;
    Ok(())
}

pub fn wait_for_ready(state_dir: &Path, timeout: Duration) -> Result<LazyMountReady> {
    let ready_path = state_dir.join(READY_FILE);
    let deadline = std::time::Instant::now() + timeout;
    loop {
        if ready_path.exists() {
            let data = fs::read_to_string(&ready_path)?;
            return serde_json::from_str(&data).map_err(|error| {
                MicError::ConfigError(format!("failed to parse mount ready file: {}", error))
            });
        }
        if std::time::Instant::now() >= deadline {
            return Err(MicError::Other(
                "Timed out waiting for lazy mount server".to_string(),
            ));
        }
        std::thread::sleep(Duration::from_millis(50));
    }
}

pub fn spawn_mount_server(state_dir: &Path) -> Result<std::process::Child> {
    let current_exe = std::env::current_exe()
        .map_err(|error| MicError::Other(format!("Failed to resolve hif binary: {}", error)))?;

    Command::new(current_exe)
        .arg("mount-serve")
        .arg("--state-dir")
        .arg(state_dir)
        .stdin(Stdio::null())
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .spawn()
        .map_err(|error| MicError::Other(format!("Failed to start lazy mount server: {}", error)))
}

pub fn mount_workspace(url: &str, mount_path: &Path) -> Result<MountActivation> {
    if cfg!(target_os = "macos") {
        return mount_workspace_macos(url, mount_path);
    }

    if cfg!(target_os = "linux") {
        return mount_workspace_linux(url, mount_path);
    }

    if cfg!(windows) {
        return mount_workspace_windows(url, mount_path);
    }

    Err(MicError::Other(
        "Lazy mount is supported on macOS, Linux, and Windows.".to_string(),
    ))
}

pub fn unmount_workspace(info: &LazyMountInfo, mount_path: &Path) -> Result<()> {
    match info.mount_kind {
        MountKind::Direct => run_command(
            "umount",
            vec![mount_path.as_os_str().to_os_string()],
            "umount",
        ),
        MountKind::LinuxGioLink => {
            remove_mount_link(mount_path)?;
            let mount_source = info.mount_source.as_deref().ok_or_else(|| {
                MicError::Other("Missing gio mount source for lazy mount.".to_string())
            })?;
            run_command(
                "gio",
                vec![os("mount"), os("-u"), os(mount_source)],
                "gio mount -u",
            )
        }
        MountKind::WindowsDriveLink => {
            remove_mount_link(mount_path)?;
            let drive = info.mount_source.as_deref().ok_or_else(|| {
                MicError::Other("Missing mapped drive for Windows lazy mount.".to_string())
            })?;
            run_command(
                "cmd",
                vec![
                    os("/C"),
                    os("NET"),
                    os("USE"),
                    os(drive),
                    os("/DELETE"),
                    os("/Y"),
                ],
                "NET USE /DELETE",
            )
        }
    }
}

fn mount_workspace_macos(url: &str, mount_path: &Path) -> Result<MountActivation> {
    run_command(
        "/sbin/mount_webdav",
        vec![os("-S"), os(url), mount_path.as_os_str().to_os_string()],
        "mount_webdav",
    )?;

    Ok(MountActivation {
        kind: MountKind::Direct,
        mount_source: None,
        link_target: None,
    })
}

#[cfg(target_os = "linux")]
fn mount_workspace_linux(url: &str, mount_path: &Path) -> Result<MountActivation> {
    let mut failures = Vec::new();

    if command_exists("mount.davfs") {
        match run_command(
            "mount.davfs",
            vec![os(url), mount_path.as_os_str().to_os_string()],
            "mount.davfs",
        ) {
            Ok(()) => {
                return Ok(MountActivation {
                    kind: MountKind::Direct,
                    mount_source: None,
                    link_target: None,
                });
            }
            Err(error) => failures.push(format!("mount.davfs: {}", error)),
        }
    } else if command_exists("mount") {
        match run_command(
            "mount",
            vec![
                os("-t"),
                os("davfs"),
                os(url),
                mount_path.as_os_str().to_os_string(),
            ],
            "mount -t davfs",
        ) {
            Ok(()) => {
                return Ok(MountActivation {
                    kind: MountKind::Direct,
                    mount_source: None,
                    link_target: None,
                });
            }
            Err(error) => failures.push(format!("mount -t davfs: {}", error)),
        }
    }

    if command_exists("gio") {
        match mount_workspace_linux_gio(url, mount_path) {
            Ok(activation) => return Ok(activation),
            Err(error) => failures.push(format!("gio mount: {}", error)),
        }
    }

    let detail = if failures.is_empty() {
        "No supported Linux WebDAV mounter was found.".to_string()
    } else {
        failures.join(" ")
    };

    Err(MicError::Other(format!(
        "Linux lazy mount requires either davfs2 mount permissions or gio/gvfs. {}",
        detail
    )))
}

#[cfg(not(target_os = "linux"))]
fn mount_workspace_linux(_url: &str, _mount_path: &Path) -> Result<MountActivation> {
    Err(MicError::Other(
        "This hif build does not include Linux lazy mount support.".to_string(),
    ))
}

#[cfg(target_os = "linux")]
fn mount_workspace_linux_gio(url: &str, mount_path: &Path) -> Result<MountActivation> {
    let before = list_gvfs_entries()?;
    run_command("gio", vec![os("mount"), os(url)], "gio mount")?;
    let target = wait_for_gvfs_mount(&before, url, Duration::from_secs(5))?;
    prepare_mount_link_path(mount_path)?;
    create_unix_symlink(&target, mount_path)?;

    Ok(MountActivation {
        kind: MountKind::LinuxGioLink,
        mount_source: Some(url.to_string()),
        link_target: Some(target.display().to_string()),
    })
}

#[cfg(target_os = "linux")]
fn list_gvfs_entries() -> Result<Vec<PathBuf>> {
    let root = gvfs_root()?;
    if !root.exists() {
        return Ok(Vec::new());
    }

    let mut entries = fs::read_dir(root)?
        .map(|entry| entry.map(|item| item.path()))
        .collect::<std::io::Result<Vec<_>>>()?;
    entries.sort();
    Ok(entries)
}

#[cfg(target_os = "linux")]
fn gvfs_root() -> Result<PathBuf> {
    if let Some(runtime_dir) = env::var_os("XDG_RUNTIME_DIR") {
        return Ok(PathBuf::from(runtime_dir).join("gvfs"));
    }

    let uid = env::var("UID")
        .ok()
        .filter(|value| !value.trim().is_empty());
    if let Some(uid) = uid {
        return Ok(PathBuf::from(format!("/run/user/{uid}/gvfs")));
    }

    let output = Command::new("id")
        .arg("-u")
        .output()
        .map_err(|error| MicError::Other(format!("Failed to resolve Linux uid: {}", error)))?;
    if !output.status.success() {
        return Err(MicError::Other(
            "Failed to resolve Linux uid via id -u.".to_string(),
        ));
    }

    let uid = String::from_utf8_lossy(&output.stdout).trim().to_string();
    Ok(PathBuf::from(format!("/run/user/{uid}/gvfs")))
}

#[cfg(target_os = "linux")]
fn wait_for_gvfs_mount(before: &[PathBuf], url: &str, timeout: Duration) -> Result<PathBuf> {
    let parsed = url::Url::parse(url)
        .map_err(|error| MicError::Other(format!("Invalid lazy mount url: {}", error)))?;
    let host = parsed.host_str().unwrap_or("127.0.0.1").to_string();
    let port = parsed.port_or_known_default();
    let deadline = std::time::Instant::now() + timeout;

    loop {
        let after = list_gvfs_entries()?;
        if let Some(found) = find_matching_gvfs_mount(before, &after, &host, port) {
            return Ok(found);
        }

        if std::time::Instant::now() >= deadline {
            return Err(MicError::Other(
                "gio mount succeeded but the gvfs path did not appear.".to_string(),
            ));
        }

        std::thread::sleep(Duration::from_millis(50));
    }
}

#[cfg(target_os = "linux")]
fn find_matching_gvfs_mount(
    before: &[PathBuf],
    after: &[PathBuf],
    host: &str,
    port: Option<u16>,
) -> Option<PathBuf> {
    let mut new_entries = after
        .iter()
        .filter(|path| !before.contains(path))
        .cloned()
        .collect::<Vec<_>>();
    new_entries.sort();

    new_entries
        .iter()
        .find(|path| gvfs_entry_matches(path, host, port))
        .cloned()
        .or_else(|| new_entries.into_iter().next())
        .or_else(|| {
            after
                .iter()
                .find(|path| gvfs_entry_matches(path, host, port))
                .cloned()
        })
}

#[cfg(target_os = "linux")]
fn gvfs_entry_matches(path: &Path, host: &str, port: Option<u16>) -> bool {
    let name = path
        .file_name()
        .and_then(|value| value.to_str())
        .unwrap_or("");
    if !name.contains(&format!("host={host}")) {
        return false;
    }

    match port {
        Some(port) => name.contains(&format!("port={port}")),
        None => true,
    }
}

fn mount_workspace_windows(url: &str, mount_path: &Path) -> Result<MountActivation> {
    let drive = find_available_windows_drive()?;
    run_command(
        "cmd",
        vec![
            os("/C"),
            os("NET"),
            os("USE"),
            os(drive.as_str()),
            os(url),
            os("/PERSISTENT:NO"),
        ],
        "NET USE",
    )?;

    let target = format!("{drive}\\");
    if let Err(error) = create_windows_mount_link(mount_path, &target) {
        let _ = run_command(
            "cmd",
            vec![
                os("/C"),
                os("NET"),
                os("USE"),
                os(drive.as_str()),
                os("/DELETE"),
                os("/Y"),
            ],
            "NET USE /DELETE",
        );
        return Err(error);
    }

    Ok(MountActivation {
        kind: MountKind::WindowsDriveLink,
        mount_source: Some(drive),
        link_target: Some(target),
    })
}

fn find_available_windows_drive() -> Result<String> {
    for letter in ('D'..='Z').rev() {
        let candidate = format!("{letter}:");
        if !Path::new(&format!("{candidate}\\")).exists() {
            return Ok(candidate);
        }
    }

    Err(MicError::Other(
        "No free Windows drive letter is available for lazy mount.".to_string(),
    ))
}

fn create_windows_mount_link(mount_path: &Path, target: &str) -> Result<()> {
    prepare_mount_link_path(mount_path)?;
    let mount_path = mount_path
        .to_str()
        .ok_or_else(|| MicError::Other("Mount path is not valid UTF-8.".to_string()))?;

    if run_command(
        "cmd",
        vec![os("/C"), os("mklink"), os("/J"), os(mount_path), os(target)],
        "mklink /J",
    )
    .is_ok()
    {
        return Ok(());
    }

    run_command(
        "cmd",
        vec![os("/C"), os("mklink"), os("/D"), os(mount_path), os(target)],
        "mklink /D",
    )
}

fn prepare_mount_link_path(mount_path: &Path) -> Result<()> {
    match fs::symlink_metadata(mount_path) {
        Ok(metadata) => {
            if metadata.file_type().is_symlink() {
                remove_mount_link(mount_path)?;
                return Ok(());
            }

            if !metadata.is_dir() {
                return Err(MicError::Other(format!(
                    "Mount path must be a directory: {}",
                    mount_path.display()
                )));
            }

            if fs::read_dir(mount_path)?.next().is_some() {
                return Err(MicError::Other(format!(
                    "Mount path must be empty before mounting: {}",
                    mount_path.display()
                )));
            }

            fs::remove_dir(mount_path)?;
            Ok(())
        }
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => Ok(()),
        Err(error) => Err(error.into()),
    }
}

fn remove_mount_link(path: &Path) -> Result<()> {
    match fs::symlink_metadata(path) {
        Ok(metadata) => {
            if metadata.is_dir() || metadata.file_type().is_symlink() {
                fs::remove_dir(path)
                    .or_else(|dir_error| fs::remove_file(path).map_err(|_| dir_error))?;
            } else {
                fs::remove_file(path)?;
            }
            Ok(())
        }
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => Ok(()),
        Err(error) => Err(error.into()),
    }
}

#[cfg(target_os = "linux")]
fn create_unix_symlink(target: &Path, link: &Path) -> Result<()> {
    std::os::unix::fs::symlink(target, link)
        .map_err(|error| MicError::Other(format!("Failed to create mount symlink: {}", error)))
}

#[cfg(target_os = "linux")]
fn command_exists(name: &str) -> bool {
    resolve_command(name).is_some()
}

#[cfg(target_os = "linux")]
fn resolve_command(name: &str) -> Option<PathBuf> {
    let candidate = PathBuf::from(name);
    if candidate.components().count() > 1 || candidate.is_absolute() {
        return candidate.exists().then_some(candidate);
    }

    let path = env::var_os("PATH")?;
    let extensions = if cfg!(windows) {
        env::var_os("PATHEXT")
            .map(|value| {
                value
                    .to_string_lossy()
                    .split(';')
                    .map(str::to_string)
                    .collect::<Vec<_>>()
            })
            .unwrap_or_else(|| vec![".COM".to_string(), ".EXE".to_string(), ".BAT".to_string()])
    } else {
        vec![String::new()]
    };

    for dir in env::split_paths(&path) {
        if cfg!(windows) && Path::new(name).extension().is_none() {
            for extension in &extensions {
                let candidate = dir.join(format!("{name}{extension}"));
                if candidate.exists() {
                    return Some(candidate);
                }
            }
        }

        let candidate = dir.join(name);
        if candidate.exists() {
            return Some(candidate);
        }
    }

    None
}

fn run_command(program: &str, args: Vec<OsString>, label: &str) -> Result<()> {
    let output = Command::new(program)
        .args(args)
        .output()
        .map_err(|error| MicError::Other(format!("Failed to execute {label}: {}", error)))?;

    if output.status.success() {
        return Ok(());
    }

    let stdout = String::from_utf8_lossy(&output.stdout).trim().to_string();
    let stderr = String::from_utf8_lossy(&output.stderr).trim().to_string();
    let detail = match (stdout.is_empty(), stderr.is_empty()) {
        (true, true) => String::new(),
        (false, true) => format!(": {}", stdout),
        (true, false) => format!(": {}", stderr),
        (false, false) => format!(": {} {}", stdout, stderr),
    };

    Err(MicError::Other(format!(
        "{label} failed with status {}{}",
        output.status, detail
    )))
}

fn os(value: impl Into<OsString>) -> OsString {
    value.into()
}

pub fn stop_mount_server(info: &LazyMountInfo) -> Result<()> {
    if let Some(pid) = info.server_pid {
        let status = Command::new("kill")
            .arg(pid.to_string())
            .status()
            .map_err(|error| MicError::Other(format!("Failed to stop mount server: {}", error)))?;

        if !status.success() {
            return Err(MicError::Other(format!(
                "kill failed with status {}",
                status
            )));
        }
    }

    Ok(())
}

pub fn workspace_mount_info(mount_path: &Path) -> Result<Option<LazyMountInfo>> {
    let path = mount_path.join(HIF_DIR).join(MOUNT_INFO_FILE);
    if !path.exists() {
        return Ok(None);
    }

    let data = fs::read_to_string(path)?;
    let info = serde_json::from_str(&data)
        .map_err(|error| MicError::ConfigError(format!("failed to parse mount info: {}", error)))?;
    Ok(Some(info))
}

pub async fn materialize_mount(info: &LazyMountInfo, mount_path: &Path) -> Result<()> {
    fs::create_dir_all(mount_path)?;
    let state = LazyMountState { info: info.clone() };
    let fs_backend = LazyMountFs::new(state.clone());
    let manifest =
        WorkspaceManifest::load_from(&state.manifest_path())?.ok_or(MicError::NoWorkspace)?;
    let tombstones = fs_backend
        .load_tombstones()
        .map_err(|_| MicError::Other("Failed to load mount tombstones".to_string()))?;

    let meta_root = state.workspace_hif_root();
    if meta_root.exists() {
        copy_tree(&meta_root, &mount_path.join(HIF_DIR))?;
    }

    for entry in &manifest.entries {
        if LazyMountFs::is_tombstoned(&tombstones, &entry.path) {
            continue;
        }

        let target = mount_path.join(&entry.path);
        if let Some(parent) = target.parent() {
            fs::create_dir_all(parent)?;
        }

        let overlay_path = state.overlay_root().join(&entry.path);
        if overlay_path.exists() {
            fs::copy(&overlay_path, &target)?;
            continue;
        }

        let cache_path = fs_backend
            .hydrate_base_file(&entry.path, entry)
            .await
            .map_err(|_| MicError::Other(format!("Failed to hydrate {}", entry.path)))?;
        fs::copy(cache_path, target)?;
    }

    copy_overlay_additions(&state.overlay_root(), mount_path, &manifest, &tombstones)?;
    remove_mount_artifacts(mount_path)?;
    Ok(())
}

fn copy_overlay_additions(
    overlay_root: &Path,
    mount_path: &Path,
    manifest: &WorkspaceManifest,
    tombstones: &HashSet<String>,
) -> Result<()> {
    if !overlay_root.exists() {
        return Ok(());
    }

    for entry in walk_files(overlay_root)? {
        let relative = entry
            .strip_prefix(overlay_root)
            .unwrap_or(&entry)
            .to_string_lossy()
            .replace('\\', "/");

        if is_mount_artifact_path(&relative) {
            continue;
        }

        if manifest.entries.iter().any(|item| item.path == relative)
            || LazyMountFs::is_tombstoned(tombstones, &relative)
        {
            continue;
        }

        let target = mount_path.join(&relative);
        if let Some(parent) = target.parent() {
            fs::create_dir_all(parent)?;
        }
        fs::copy(&entry, target)?;
    }

    Ok(())
}

fn walk_files(root: &Path) -> Result<Vec<PathBuf>> {
    let mut files = Vec::new();
    if !root.exists() {
        return Ok(files);
    }

    fn visit(current: &Path, files: &mut Vec<PathBuf>) -> std::io::Result<()> {
        for entry in fs::read_dir(current)? {
            let entry = entry?;
            let path = entry.path();
            if path.is_dir() {
                visit(&path, files)?;
            } else {
                files.push(path);
            }
        }
        Ok(())
    }

    visit(root, &mut files)?;
    Ok(files)
}

fn remove_mount_artifacts(root: &Path) -> Result<()> {
    for path in walk_files(root)? {
        let relative = path
            .strip_prefix(root)
            .unwrap_or(&path)
            .to_string_lossy()
            .replace('\\', "/");

        if is_mount_artifact_path(&relative) {
            fs::remove_file(&path)?;
        }
    }

    Ok(())
}

fn is_mount_artifact_path(relative: &str) -> bool {
    relative
        .split('/')
        .any(|component| component == ".DS_Store" || component.starts_with("._"))
}

fn copy_tree(from: &Path, to: &Path) -> Result<()> {
    if !from.exists() {
        return Ok(());
    }

    for entry in fs::read_dir(from)? {
        let entry = entry?;
        let path = entry.path();
        let target = to.join(entry.file_name());
        if path.is_dir() {
            fs::create_dir_all(&target)?;
            copy_tree(&path, &target)?;
        } else {
            if let Some(parent) = target.parent() {
                fs::create_dir_all(parent)?;
            }
            fs::copy(&path, &target)?;
        }
    }

    Ok(())
}

fn encode_hex(bytes: &[u8]) -> String {
    bytes
        .iter()
        .map(|byte| format!("{:02x}", byte))
        .collect::<String>()
}

pub async fn serve(cmd: MountServeCommand) -> Result<()> {
    let info = load_mount_info(&cmd.state_dir)?;
    let state = LazyMountState { info: info.clone() };
    let dav_handler = DavHandler::builder()
        .filesystem(Box::new(LazyMountFs::new(state.clone())))
        .locksystem(FakeLs::new())
        .build_handler();

    let address = SocketAddr::from(([127, 0, 0, 1], info.port));
    let listener = TcpListener::bind(address)
        .await
        .map_err(|error| MicError::Other(format!("Failed to bind mount server: {}", error)))?;

    let ready = LazyMountReady {
        pid: std::process::id(),
        port: info.port,
    };
    let ready_data = serde_json::to_string_pretty(&ready).map_err(|error| {
        MicError::Other(format!("Failed to serialize mount readiness: {}", error))
    })?;
    fs::write(state.ready_path(), ready_data)?;

    loop {
        let (stream, _) = listener.accept().await.map_err(|error| {
            MicError::Other(format!("Failed to accept mount request: {}", error))
        })?;
        let handler = dav_handler.clone();

        tokio::task::spawn(async move {
            let io = TokioIo::new(stream);
            let service = service_fn(move |request: Request<Incoming>| {
                let handler = handler.clone();
                async move { Ok::<_, Infallible>(handler.handle(request).await) }
            });

            let _ = http1::Builder::new().serve_connection(io, service).await;
        });
    }
}
