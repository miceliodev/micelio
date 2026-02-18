defmodule MicelioWeb.Browser.ApiTryController do
  @moduledoc """
  Session-authenticated proxy for interactive API "try it" examples in the docs.

  Sits in the browser pipeline so it gets session auth from AuthenticationPlug.
  Validates requested endpoints against an allowlist, then calls the same context
  functions the real API controllers use.
  """
  use MicelioWeb, :controller

  alias Micelio.Accounts
  alias Micelio.Authorization
  alias Micelio.Mic.Binary
  alias Micelio.Mic.DeltaCompression
  alias Micelio.Mic.Tree, as: MicTree
  alias Micelio.Plans
  alias Micelio.Repositories
  alias Micelio.Sessions
  alias Micelio.Storage
  alias MicelioWeb.Api.Helpers

  def proxy(conn, %{"method" => method, "path" => path} = params) do
    user = conn.assigns[:current_user]

    if is_nil(user) do
      conn
      |> put_status(401)
      |> json(%{error: "unauthenticated", error_description: "Sign in to try API requests."})
    else
      body = Map.get(params, "body", %{})
      dispatch(conn, user, String.upcase(method), path, body)
    end
  end

  # GET /api/orgs
  defp dispatch(conn, user, "GET", "/api/orgs", _body) do
    organizations = Accounts.list_organizations_for_user(user)

    json(conn, %{
      data:
        Enum.map(organizations, fn org ->
          handle = if org.account, do: org.account.handle

          %{
            id: org.id,
            handle: handle,
            name: org.name,
            inserted_at: Helpers.format_datetime(org.inserted_at),
            updated_at: Helpers.format_datetime(org.updated_at)
          }
        end)
    })
  end

  # GET /api/orgs/:handle and sub-resources
  defp dispatch(conn, user, "GET", "/api/orgs/" <> rest, _body) do
    case String.split(rest, "/") do
      # GET /api/orgs/:handle
      [handle] ->
        with {:ok, org} <- Helpers.fetch_organization(handle),
             member? = Accounts.user_in_organization?(user, org),
             true <- member? do
          org_handle = if org.account, do: org.account.handle

          json(conn, %{
            data: %{
              id: org.id,
              handle: org_handle,
              name: org.name,
              inserted_at: Helpers.format_datetime(org.inserted_at),
              updated_at: Helpers.format_datetime(org.updated_at)
            }
          })
        else
          _ -> json_error(conn, 404, "not_found", "Organization not found")
        end

      [org_handle, "repositories"] ->
        case fetch_org_repos(org_handle, user) do
          {:ok, _org, repos} ->
            json(conn, %{
              data:
                Enum.map(repos, fn repo ->
                  serialize_repository(repo, org_handle)
                end)
            })

          _ ->
            json_error(conn, 404, "not_found", "Organization not found")
        end

      # GET /api/orgs/:org/repositories/:repo
      [org_handle, "repositories", repo_handle] ->
        with {:ok, _org, repository} <- Helpers.fetch_repository(org_handle, repo_handle),
             :ok <- Authorization.authorize(:repository_read, user, repository) do
          json(conn, %{data: serialize_repository(repository, org_handle)})
        else
          _ -> json_error(conn, 404, "not_found", "Repository not found")
        end

      # GET /api/orgs/:org/repositories/:repo/sessions
      [org_handle, "repositories", repo_handle, "sessions"] ->
        with {:ok, _org, repository} <- Helpers.fetch_repository(org_handle, repo_handle),
             :ok <- Authorization.authorize(:repository_read, user, repository) do
          sessions = Sessions.list_sessions_for_repository(repository)
          json(conn, %{data: Enum.map(sessions, &serialize_session/1)})
        else
          _ -> json_error(conn, 404, "not_found", "Repository not found")
        end

      # GET /api/orgs/:org/repositories/:repo/plans
      [org_handle, "repositories", repo_handle, "plans"] ->
        with {:ok, _org, repository} <- Helpers.fetch_repository(org_handle, repo_handle),
             :ok <- Authorization.authorize(:repository_read, user, repository) do
          plans = Plans.list_plans_for_repository(repository)
          json(conn, %{data: Enum.map(plans, &serialize_plan/1)})
        else
          _ -> json_error(conn, 404, "not_found", "Repository not found")
        end

      # GET /api/orgs/:org/repositories/:repo/plans/:number
      [org_handle, "repositories", repo_handle, "plans", number] ->
        with {:ok, _org, repository} <- Helpers.fetch_repository(org_handle, repo_handle),
             :ok <- Authorization.authorize(:repository_read, user, repository),
             %Plans.Plan{} = plan <-
               Plans.get_plan_by_number(repository, number) do
          json(conn, %{data: serialize_plan(plan)})
        else
          _ -> json_error(conn, 404, "not_found", "Plan not found")
        end

      # GET /api/orgs/:org/repositories/:repo/tree
      [org_handle, "repositories", repo_handle, "tree"] ->
        with {:ok, _org, repository} <- Helpers.fetch_repository(org_handle, repo_handle),
             :ok <- Authorization.authorize(:repository_read, user, repository),
             {:ok, _tree_hash, tree} <- load_head_tree(repository.id) do
          entries =
            tree
            |> Map.to_list()
            |> Enum.sort_by(fn {path, _hash} -> path end)
            |> Enum.map(fn {path, _hash} -> %{name: path, type: "blob"} end)

          json(conn, %{data: entries})
        else
          _ -> json_error(conn, 404, "not_found", "Repository or tree not found")
        end

      # GET /api/orgs/:org/repositories/:repo/blob/...
      [org_handle, "repositories", repo_handle, "blob" | path_parts]
      when path_parts != [] ->
        file_path = Enum.join(path_parts, "/")

        with {:ok, _org, repository} <- Helpers.fetch_repository(org_handle, repo_handle),
             :ok <- Authorization.authorize(:repository_read, user, repository),
             {:ok, _tree_hash, tree} <- load_head_tree(repository.id),
             {:ok, blob_hash} <- fetch_path_hash(tree, file_path),
             {:ok, content} <- load_blob(repository.id, blob_hash) do
          {encoded, encoding} =
            if String.valid?(content) do
              {content, "utf-8"}
            else
              {Base.encode64(content), "base64"}
            end

          json(conn, %{data: %{content: encoded, encoding: encoding, size: byte_size(content)}})
        else
          _ -> json_error(conn, 404, "not_found", "File not found")
        end

      _ ->
        json_error(
          conn,
          403,
          "forbidden",
          "This endpoint is not available for interactive testing."
        )
    end
  end

  # POST endpoints
  defp dispatch(conn, user, "POST", "/api/orgs/" <> rest, body) do
    case String.split(rest, "/") do
      # POST /api/orgs/:org/repositories/:repo/plans
      [org_handle, "repositories", repo_handle, "plans"] ->
        with {:ok, _org, repository} <- Helpers.fetch_repository(org_handle, repo_handle),
             :ok <- Authorization.authorize(:repository_write, user, repository) do
          attrs = Map.take(body, ["title", "description"])

          case Plans.create_simple_plan(attrs,
                 repository: repository,
                 user: user
               ) do
            {:ok, plan} ->
              conn |> put_status(201) |> json(%{data: serialize_plan(plan)})

            {:error, %Ecto.Changeset{} = changeset} ->
              json_error(conn, 422, "validation_error", changeset_message(changeset))
          end
        else
          _ -> json_error(conn, 404, "not_found", "Repository not found")
        end

      # POST /api/orgs/:org/repositories/:repo/plans/:number/close
      [org_handle, "repositories", repo_handle, "plans", number, "close"] ->
        with {:ok, _org, repository} <- Helpers.fetch_repository(org_handle, repo_handle),
             :ok <- Authorization.authorize(:repository_write, user, repository),
             %Plans.Plan{} = plan <-
               Plans.get_plan_by_number(repository, number),
             {:ok, closed} <- Plans.close_plan(plan) do
          json(conn, %{data: serialize_plan(closed)})
        else
          _ -> json_error(conn, 404, "not_found", "Plan not found")
        end

      # POST /api/orgs/:org/repositories/:repo/plans/:number/reopen
      [org_handle, "repositories", repo_handle, "plans", number, "reopen"] ->
        with {:ok, _org, repository} <- Helpers.fetch_repository(org_handle, repo_handle),
             :ok <- Authorization.authorize(:repository_write, user, repository),
             %Plans.Plan{} = plan <-
               Plans.get_plan_by_number(repository, number),
             {:ok, reopened} <- Plans.reopen_plan(plan) do
          json(conn, %{data: serialize_plan(reopened)})
        else
          _ -> json_error(conn, 404, "not_found", "Plan not found")
        end

      # POST /api/orgs/:org/repositories/:repo/sessions
      [org_handle, "repositories", repo_handle, "sessions"] ->
        with {:ok, _org, repository} <- Helpers.fetch_repository(org_handle, repo_handle),
             :ok <- Authorization.authorize(:repository_write, user, repository) do
          session_attrs = %{
            "goal" => body["goal"],
            "repository_id" => repository.id,
            "user_id" => user.id,
            "session_id" => Ecto.UUID.generate(),
            "status" => "active",
            "started_at" => DateTime.utc_now() |> DateTime.truncate(:second)
          }

          case Sessions.create_session(session_attrs) do
            {:ok, session} ->
              conn |> put_status(201) |> json(%{data: serialize_session(session)})

            {:error, %Ecto.Changeset{} = changeset} ->
              json_error(conn, 422, "validation_error", changeset_message(changeset))
          end
        else
          _ -> json_error(conn, 404, "not_found", "Repository not found")
        end

      _ ->
        json_error(
          conn,
          403,
          "forbidden",
          "This endpoint is not available for interactive testing."
        )
    end
  end

  # PATCH /api/orgs/:org/repositories/:repo/plans/:number
  defp dispatch(conn, user, "PATCH", "/api/orgs/" <> rest, body) do
    case String.split(rest, "/") do
      [org_handle, "repositories", repo_handle, "plans", number] ->
        with {:ok, _org, repository} <- Helpers.fetch_repository(org_handle, repo_handle),
             :ok <- Authorization.authorize(:repository_write, user, repository),
             %Plans.Plan{} = plan <-
               Plans.get_plan_by_number(repository, number) do
          attrs = Map.take(body, ["title", "description"])

          case Plans.update_plan(plan, attrs) do
            {:ok, updated} ->
              json(conn, %{data: serialize_plan(updated)})

            {:error, %Ecto.Changeset{} = changeset} ->
              json_error(conn, 422, "validation_error", changeset_message(changeset))
          end
        else
          _ -> json_error(conn, 404, "not_found", "Plan not found")
        end

      _ ->
        json_error(
          conn,
          403,
          "forbidden",
          "This endpoint is not available for interactive testing."
        )
    end
  end

  defp dispatch(conn, _user, _method, _path, _body) do
    json_error(conn, 403, "forbidden", "This endpoint is not available for interactive testing.")
  end

  # Helpers

  defp json_error(conn, status, error, description) do
    conn
    |> put_status(status)
    |> json(%{error: error, error_description: description})
  end

  defp fetch_org_repos(org_handle, _user) do
    with {:ok, org} <- Helpers.fetch_organization(org_handle) do
      repos = Repositories.list_repositories_for_organization(org.id)
      {:ok, org, repos}
    end
  end

  defp serialize_repository(repo, org_handle) do
    %{
      id: repo.id,
      handle: repo.handle,
      name: repo.name,
      description: repo.description,
      visibility: repo.visibility,
      organization_handle: org_handle,
      inserted_at: Helpers.format_datetime(repo.inserted_at),
      updated_at: Helpers.format_datetime(repo.updated_at)
    }
  end

  defp serialize_session(session) do
    %{
      id: session.id,
      session_id: session.session_id,
      goal: session.goal,
      status: session.status,
      started_at: Helpers.format_datetime(session.started_at),
      landed_at: Helpers.format_datetime(session.landed_at),
      inserted_at: Helpers.format_datetime(session.inserted_at),
      updated_at: Helpers.format_datetime(session.updated_at)
    }
  end

  defp serialize_plan(plan) do
    %{
      id: plan.id,
      number: plan.number,
      title: plan.title,
      description: plan.description,
      status: plan.status,
      user: serialize_plan_user(plan.user),
      inserted_at: Helpers.format_datetime(plan.inserted_at),
      updated_at: Helpers.format_datetime(plan.updated_at)
    }
  end

  defp serialize_plan_user(nil), do: nil
  defp serialize_plan_user(%Ecto.Association.NotLoaded{}), do: nil
  defp serialize_plan_user(user), do: %{id: user.id, email: user.email}

  defp changeset_message(%Ecto.Changeset{} = changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, _opts} -> msg end)
    |> Enum.map_join(", ", fn {field, msgs} -> "#{field}: #{Enum.join(msgs, ", ")}" end)
  end

  # Storage helpers (same as ContentController)

  @zero_hash <<0::size(256)>>

  defp load_head_tree(repository_id) do
    case Storage.get("projects/#{repository_id}/head") do
      {:ok, content} ->
        with {:ok, head} <- Binary.decode_head(content),
             {:ok, tree} <- load_tree(repository_id, head.tree_hash) do
          {:ok, head.tree_hash, tree}
        else
          _ -> {:error, :not_found}
        end

      {:error, :not_found} ->
        {:ok, Binary.zero_hash(), MicTree.empty()}

      _ ->
        {:error, :not_found}
    end
  end

  defp load_tree(_repository_id, tree_hash) when tree_hash == @zero_hash,
    do: {:ok, MicTree.empty()}

  defp load_tree(repository_id, tree_hash) do
    hash_hex = Base.encode16(tree_hash, case: :lower)
    prefix = String.slice(hash_hex, 0, 2)

    case Storage.get("projects/#{repository_id}/trees/#{prefix}/#{hash_hex}.bin") do
      {:ok, content} ->
        case MicTree.decode(content) do
          {:ok, tree} -> {:ok, tree}
          _ -> {:error, :not_found}
        end

      _ ->
        {:error, :not_found}
    end
  end

  defp load_blob(repository_id, blob_hash) do
    hash_hex = Base.encode16(blob_hash, case: :lower)
    prefix = String.slice(hash_hex, 0, 2)
    key = "projects/#{repository_id}/blobs/#{prefix}/#{hash_hex}.bin"

    case Storage.get(key) do
      {:ok, content} ->
        case DeltaCompression.decode(content, fn hash ->
               inner_hex = Base.encode16(hash, case: :lower)
               inner_prefix = String.slice(inner_hex, 0, 2)
               Storage.get("projects/#{repository_id}/blobs/#{inner_prefix}/#{inner_hex}.bin")
             end) do
          {:ok, decoded} -> {:ok, decoded}
          _ -> {:error, :not_found}
        end

      _ ->
        {:error, :not_found}
    end
  end

  defp fetch_path_hash(tree, path) do
    case Map.fetch(tree, path) do
      {:ok, hash} -> {:ok, hash}
      :error -> {:error, :path_not_found}
    end
  end
end
