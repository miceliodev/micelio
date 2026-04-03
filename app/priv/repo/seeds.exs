# Seeds for local development
#
# Creates a simple Node.js repository and materializes it into seeds/workspace/
# so the hif CLI can interact with the server locally.
alias Micelio.Accounts
alias Micelio.Accounts.OrganizationMembership
alias Micelio.Mic.Project, as: MicProject
alias Micelio.Mic.Seed
alias Micelio.Repo
alias Micelio.Repositories
alias Micelio.Repositories.Repository

user_email = "test@micelio.dev"
org_handle = "micelio"
org_name = "Micelio"
repo_handle = "cli-seed"
repo_name = "cli-seed"
repo_description = "A simple Node.js starter project"
repo_url = "https://micelio.dev"
repo_visibility = "public"
grpc_url = System.get_env("MICELIO_GRPC_URL") || "http://localhost:50051"

workspace_root = Path.join([File.cwd!(), "..", "seeds", "workspace"])

# ---------------------------------------------------------------------------
# 1. Ensure user, organization, and membership
# ---------------------------------------------------------------------------

organization_result =
  case Accounts.get_organization_by_handle(org_handle) do
    {:ok, org} ->
      {:ok, org}

    {:error, :not_found} ->
      Accounts.create_organization(%{handle: org_handle, name: org_name}, allow_reserved: true)
  end

with {:ok, user} <- Accounts.get_or_create_user_by_email(user_email),
     {:ok, organization} <- organization_result do
  case Accounts.get_organization_membership(user.id, organization.id) do
    nil ->
      {:ok, _membership} =
        Accounts.create_organization_membership(%{
          user_id: user.id,
          organization_id: organization.id,
          role: :admin
        })

    %OrganizationMembership{role: :admin} ->
      :ok

    %OrganizationMembership{} = membership ->
      {:ok, _membership} =
        membership
        |> OrganizationMembership.changeset(%{role: :admin})
        |> Repo.update()
  end

  # ---------------------------------------------------------------------------
  # 2. Ensure repository record
  # ---------------------------------------------------------------------------

  repo_attrs = %{
    handle: repo_handle,
    name: repo_name,
    description: repo_description,
    url: repo_url,
    visibility: repo_visibility,
    organization_id: organization.id
  }

  repository =
    case Repositories.get_repository_by_handle(organization.id, repo_handle) do
      nil ->
        case Repositories.create_repository(repo_attrs) do
          {:ok, repo} -> repo
          {:error, reason} -> raise "Failed to create repository: #{inspect(reason)}"
        end

      %Repository{} = repo ->
        repo
    end

  IO.puts("Ensured repository: #{org_handle}/#{repository.handle}")

  # ---------------------------------------------------------------------------
  # 3. Write seed files into workspace and seed storage
  # ---------------------------------------------------------------------------

  File.rm_rf!(workspace_root)
  File.mkdir_p!(workspace_root)

  seed_files = %{
    "package.json" => ~s|{
  "name": "hello",
  "version": "1.0.0",
  "description": "A simple Node.js starter project",
  "main": "main.js",
  "scripts": {
    "start": "node main.js"
  },
  "license": "MIT"
}
|,
    "main.js" => ~s|#!/usr/bin/env node

function greet(name) {
  return `Hello, ${name}!`;
}

console.log(greet("world"));
|,
    "README.md" => ~s|# hello

A simple Node.js starter project.

## Usage

```bash
npm start
```
|,
    "AGENTS.md" => ~s|# Agent Guide

This repository is a minimal Node.js project.

## Structure

- `main.js` - Entry point
- `package.json` - Project metadata

## Running

```bash
node main.js
```
|,
    "LICENSE.md" => ~s|MIT License

Copyright (c) 2026 Micelio

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
|
  }

  for {path, content} <- seed_files do
    full_path = Path.join(workspace_root, path)
    File.write!(full_path, content)
  end

  IO.puts("Wrote #{map_size(seed_files)} files to #{workspace_root}")

  # Seed storage from the workspace directory
  seed_result =
    case Seed.seed_repository_from_path(repository.id, workspace_root) do
      {:ok, %{tree_hash: tree_hash} = result} ->
        IO.puts("Seeded #{result.file_count} files into storage")
        {:seeded, tree_hash, result}

      {:error, :already_seeded} ->
        IO.puts("Repository already seeded, updating tree...")

        case Seed.store_tree_from_path(repository.id, workspace_root) do
          {:ok, %{tree_hash: tree_hash} = result} ->
            IO.puts("Updated tree with #{result.file_count} files")
            {:updated, tree_hash, result}

          {:error, reason} ->
            raise "Failed to update tree: #{inspect(reason)}"
        end

      {:error, reason} ->
        raise "Failed to seed workspace: #{inspect(reason)}"
    end

  {position, tree_hash} =
    case MicProject.get_head(repository.id) do
      {:ok, %{position: position, tree_hash: head_hash}} ->
        {position, head_hash}

      {:ok, nil} ->
        {1, elem(seed_result, 1)}

      {:error, reason} ->
        raise "Failed to read head: #{inspect(reason)}"
    end

  if not is_binary(tree_hash) do
    raise "Failed to resolve workspace tree hash"
  end

  # ---------------------------------------------------------------------------
  # 4. Write .hif/workspace.json manifest for CLI interaction
  # ---------------------------------------------------------------------------

  {:ok, tree} = MicProject.get_tree(repository.id, tree_hash)

  manifest = %{
    "version" => 1,
    "server" => grpc_url,
    "account" => org_handle,
    "repository" => repository.handle,
    "position" => position,
    "tree_hash" => Base.encode16(tree_hash, case: :lower),
    "entries" =>
      tree
      |> Enum.sort_by(fn {path, _hash} -> path end)
      |> Enum.map(fn {path, hash} ->
        %{"path" => path, "hash" => Base.encode16(hash, case: :lower)}
      end)
  }

  hif_dir = Path.join(workspace_root, ".hif")
  File.mkdir_p!(hif_dir)
  File.write!(Path.join(hif_dir, "workspace.json"), Jason.encode!(manifest, pretty: true))

  IO.puts("Wrote .hif/workspace.json (position=#{position})")

  # ---------------------------------------------------------------------------
  # 5. Done
  # ---------------------------------------------------------------------------

  IO.puts("\nLocal development setup complete!")
  IO.puts("  Repository: #{org_handle}/#{repository.handle}")
  IO.puts("  Workspace:  #{workspace_root}")
  IO.puts("  Sessions:   none seeded")
  IO.puts("  Login with: #{user.email}")
  IO.puts("  gRPC:       #{grpc_url}")
else
  {:error, reason} ->
    raise "Failed to ensure Micelio seed data: #{inspect(reason)}"
end
