const std = @import("std");
const beam = @import("beam");
const git = @cImport({
    @cInclude("git2.h");
});

// =============================================================================
// Shared utilities
// =============================================================================

fn init_libgit2() !void {
    const result = git.git_libgit2_init();
    if (result < 0) {
        return error.LibGit2InitFailed;
    }
}

fn shutdown_libgit2() void {
    _ = git.git_libgit2_shutdown();
}

fn null_terminate(path: []const u8, buf: *[4096]u8) ?[*:0]const u8 {
    if (path.len >= buf.len) {
        return null;
    }
    @memcpy(buf[0..path.len], path);
    buf[path.len] = 0;
    return @ptrCast(buf[0..path.len :0]);
}

fn null_terminate_small(path: []const u8, buf: *[256]u8) ?[*:0]const u8 {
    if (path.len >= buf.len) {
        return null;
    }
    @memcpy(buf[0..path.len], path);
    buf[path.len] = 0;
    return @ptrCast(buf[0..path.len :0]);
}

// =============================================================================
// Status operations (status domain)
// =============================================================================

/// Returns the git status for the repository at the given path
pub fn status(path: []const u8) beam.term {
    init_libgit2() catch {
        return beam.make(.{ .@"error", .libgit2_init_failed }, .{});
    };
    defer shutdown_libgit2();

    var path_buf: [4096]u8 = undefined;
    const path_z = null_terminate(path, &path_buf) orelse {
        return beam.make(.{ .@"error", .path_too_long }, .{});
    };

    var repo: ?*git.git_repository = null;
    if (git.git_repository_open(&repo, path_z) < 0) {
        return beam.make(.{ .@"error", .repository_not_found }, .{});
    }
    defer git.git_repository_free(repo);

    var status_list: ?*git.git_status_list = null;
    var opts: git.git_status_options = undefined;
    _ = git.git_status_options_init(&opts, git.GIT_STATUS_OPTIONS_VERSION);
    opts.show = git.GIT_STATUS_SHOW_INDEX_AND_WORKDIR;
    opts.flags = git.GIT_STATUS_OPT_INCLUDE_UNTRACKED |
        git.GIT_STATUS_OPT_RENAMES_HEAD_TO_INDEX |
        git.GIT_STATUS_OPT_SORT_CASE_SENSITIVELY;

    const status_result = git.git_status_list_new(&status_list, repo, &opts);
    if (status_result < 0) {
        return beam.make(.{ .@"error", .status_failed }, .{});
    }
    defer git.git_status_list_free(status_list);

    const count = git.git_status_list_entrycount(status_list);
    var results: [1024]beam.term = undefined;
    var result_count: usize = 0;

    for (0..count) |i| {
        if (result_count >= results.len) break;

        const entry = git.git_status_byindex(status_list, i);
        if (entry != null) {
            const e = entry.?;
            var file_path: []const u8 = undefined;

            if (e.*.head_to_index != null) {
                file_path = std.mem.span(e.*.head_to_index.*.new_file.path);
            } else if (e.*.index_to_workdir != null) {
                file_path = std.mem.span(e.*.index_to_workdir.*.new_file.path);
            } else {
                continue;
            }

            const status_flags = e.*.status;
            const status_str = status_to_string(status_flags);

            results[result_count] = beam.make(.{ file_path, status_str }, .{});
            result_count += 1;
        }
    }

    return beam.make(.{ .ok, results[0..result_count] }, .{});
}

fn status_to_string(flags: c_uint) []const u8 {
    if (flags & git.GIT_STATUS_INDEX_NEW != 0) return "new";
    if (flags & git.GIT_STATUS_INDEX_MODIFIED != 0) return "modified";
    if (flags & git.GIT_STATUS_INDEX_DELETED != 0) return "deleted";
    if (flags & git.GIT_STATUS_INDEX_RENAMED != 0) return "renamed";
    if (flags & git.GIT_STATUS_INDEX_TYPECHANGE != 0) return "typechange";
    if (flags & git.GIT_STATUS_WT_NEW != 0) return "untracked";
    if (flags & git.GIT_STATUS_WT_MODIFIED != 0) return "modified";
    if (flags & git.GIT_STATUS_WT_DELETED != 0) return "deleted";
    if (flags & git.GIT_STATUS_WT_TYPECHANGE != 0) return "typechange";
    if (flags & git.GIT_STATUS_WT_RENAMED != 0) return "renamed";
    if (flags & git.GIT_STATUS_IGNORED != 0) return "ignored";
    if (flags & git.GIT_STATUS_CONFLICTED != 0) return "conflicted";
    return "unknown";
}

// =============================================================================
// Repository operations (repository domain)
// =============================================================================

/// Initializes a new Git repository at the given path
pub fn repository_init(path: []const u8) beam.term {
    init_libgit2() catch {
        return beam.make(.{ .@"error", .libgit2_init_failed }, .{});
    };
    defer shutdown_libgit2();

    var path_buf: [4096]u8 = undefined;
    const path_z = null_terminate(path, &path_buf) orelse {
        return beam.make(.{ .@"error", .path_too_long }, .{});
    };

    var repo: ?*git.git_repository = null;
    if (git.git_repository_init(&repo, path_z, 0) < 0) {
        return beam.make(.{ .@"error", .repository_init_failed }, .{});
    }
    defer git.git_repository_free(repo);

    return beam.make(.ok, .{});
}

/// Returns the default branch name for the repository
pub fn repository_default_branch(path: []const u8) beam.term {
    init_libgit2() catch {
        return beam.make(.{ .@"error", .libgit2_init_failed }, .{});
    };
    defer shutdown_libgit2();

    var path_buf: [4096]u8 = undefined;
    const path_z = null_terminate(path, &path_buf) orelse {
        return beam.make(.{ .@"error", .path_too_long }, .{});
    };

    var repo: ?*git.git_repository = null;
    if (git.git_repository_open(&repo, path_z) < 0) {
        return beam.make(.{ .@"error", .repository_not_found }, .{});
    }
    defer git.git_repository_free(repo);

    var head: ?*git.git_reference = null;
    if (git.git_repository_head(&head, repo) < 0) {
        return beam.make(.{ .@"error", .head_not_found }, .{});
    }
    defer git.git_reference_free(head);

    const name = git.git_reference_shorthand(head);
    if (name == null) {
        return beam.make(.{ .@"error", .branch_name_not_found }, .{});
    }

    return beam.make(.{ .ok, std.mem.span(name) }, .{});
}

// =============================================================================
// Tree operations (tree domain)
// =============================================================================

/// Lists entries in a tree at the given ref and path
pub fn tree_list(repo_path: []const u8, ref: []const u8, tree_path: []const u8) beam.term {
    init_libgit2() catch {
        return beam.make(.{ .@"error", .libgit2_init_failed }, .{});
    };
    defer shutdown_libgit2();

    var path_buf: [4096]u8 = undefined;
    const path_z = null_terminate(repo_path, &path_buf) orelse {
        return beam.make(.{ .@"error", .path_too_long }, .{});
    };

    var repo: ?*git.git_repository = null;
    if (git.git_repository_open(&repo, path_z) < 0) {
        return beam.make(.{ .@"error", .repository_not_found }, .{});
    }
    defer git.git_repository_free(repo);

    var ref_buf: [256]u8 = undefined;
    const ref_z = null_terminate_small(ref, &ref_buf) orelse {
        return beam.make(.{ .@"error", .ref_too_long }, .{});
    };

    var obj: ?*git.git_object = null;
    if (git.git_revparse_single(&obj, repo, ref_z) < 0) {
        return beam.make(.{ .@"error", .ref_not_found }, .{});
    }
    defer git.git_object_free(obj);

    var commit: ?*git.git_commit = null;
    if (git.git_commit_lookup(&commit, repo, git.git_object_id(obj)) < 0) {
        return beam.make(.{ .@"error", .commit_not_found }, .{});
    }
    defer git.git_commit_free(commit);

    var root_tree: ?*git.git_tree = null;
    if (git.git_commit_tree(&root_tree, commit) < 0) {
        return beam.make(.{ .@"error", .tree_not_found }, .{});
    }
    defer git.git_tree_free(root_tree);

    var target_tree: ?*git.git_tree = root_tree;
    var subtree: ?*git.git_tree = null;

    if (tree_path.len > 0) {
        var tree_path_buf: [4096]u8 = undefined;
        const tree_path_z = null_terminate(tree_path, &tree_path_buf) orelse {
            return beam.make(.{ .@"error", .path_too_long }, .{});
        };

        var entry: ?*git.git_tree_entry = null;
        if (git.git_tree_entry_bypath(&entry, root_tree, tree_path_z) < 0) {
            return beam.make(.{ .@"error", .path_not_found }, .{});
        }
        defer git.git_tree_entry_free(entry);

        if (git.git_tree_lookup(&subtree, repo, git.git_tree_entry_id(entry)) < 0) {
            return beam.make(.{ .@"error", .subtree_not_found }, .{});
        }
        target_tree = subtree;
    }
    defer if (subtree != null) git.git_tree_free(subtree);

    const count = git.git_tree_entrycount(target_tree);
    var results: [1024]beam.term = undefined;
    var result_count: usize = 0;

    for (0..count) |i| {
        if (result_count >= results.len) break;

        const entry = git.git_tree_entry_byindex(target_tree, i);
        if (entry != null) {
            const name = std.mem.span(git.git_tree_entry_name(entry));
            const entry_type = git.git_tree_entry_type(entry);
            const type_str = switch (entry_type) {
                git.GIT_OBJECT_BLOB => "blob",
                git.GIT_OBJECT_TREE => "tree",
                git.GIT_OBJECT_COMMIT => "commit",
                else => "unknown",
            };

            var oid_buf: [41]u8 = undefined;
            _ = git.git_oid_tostr(&oid_buf, oid_buf.len, git.git_tree_entry_id(entry));
            const oid_str = std.mem.sliceTo(&oid_buf, 0);

            results[result_count] = beam.make(.{ name, type_str, oid_str }, .{});
            result_count += 1;
        }
    }

    return beam.make(.{ .ok, results[0..result_count] }, .{});
}

/// Reads the content of a blob at the given ref and path
pub fn tree_blob(repo_path: []const u8, ref: []const u8, file_path: []const u8) beam.term {
    init_libgit2() catch {
        return beam.make(.{ .@"error", .libgit2_init_failed }, .{});
    };
    defer shutdown_libgit2();

    var path_buf: [4096]u8 = undefined;
    const path_z = null_terminate(repo_path, &path_buf) orelse {
        return beam.make(.{ .@"error", .path_too_long }, .{});
    };

    var repo: ?*git.git_repository = null;
    if (git.git_repository_open(&repo, path_z) < 0) {
        return beam.make(.{ .@"error", .repository_not_found }, .{});
    }
    defer git.git_repository_free(repo);

    var ref_buf: [256]u8 = undefined;
    const ref_z = null_terminate_small(ref, &ref_buf) orelse {
        return beam.make(.{ .@"error", .ref_too_long }, .{});
    };

    var obj: ?*git.git_object = null;
    if (git.git_revparse_single(&obj, repo, ref_z) < 0) {
        return beam.make(.{ .@"error", .ref_not_found }, .{});
    }
    defer git.git_object_free(obj);

    var commit: ?*git.git_commit = null;
    if (git.git_commit_lookup(&commit, repo, git.git_object_id(obj)) < 0) {
        return beam.make(.{ .@"error", .commit_not_found }, .{});
    }
    defer git.git_commit_free(commit);

    var root_tree: ?*git.git_tree = null;
    if (git.git_commit_tree(&root_tree, commit) < 0) {
        return beam.make(.{ .@"error", .tree_not_found }, .{});
    }
    defer git.git_tree_free(root_tree);

    var file_path_buf: [4096]u8 = undefined;
    const file_path_z = null_terminate(file_path, &file_path_buf) orelse {
        return beam.make(.{ .@"error", .path_too_long }, .{});
    };

    var entry: ?*git.git_tree_entry = null;
    if (git.git_tree_entry_bypath(&entry, root_tree, file_path_z) < 0) {
        return beam.make(.{ .@"error", .file_not_found }, .{});
    }
    defer git.git_tree_entry_free(entry);

    if (git.git_tree_entry_type(entry) != git.GIT_OBJECT_BLOB) {
        return beam.make(.{ .@"error", .not_a_file }, .{});
    }

    var blob_obj: ?*git.git_blob = null;
    if (git.git_blob_lookup(&blob_obj, repo, git.git_tree_entry_id(entry)) < 0) {
        return beam.make(.{ .@"error", .blob_not_found }, .{});
    }
    defer git.git_blob_free(blob_obj);

    const content = git.git_blob_rawcontent(blob_obj);
    const size = git.git_blob_rawsize(blob_obj);

    if (content == null or size < 0) {
        return beam.make(.{ .@"error", .blob_content_error }, .{});
    }

    const content_ptr: [*]const u8 = @ptrCast(content.?);
    const content_slice = content_ptr[0..@intCast(size)];
    return beam.make(.{ .ok, content_slice }, .{});
}
