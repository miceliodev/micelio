defmodule Micelio.Repositories do
  @moduledoc """
  The Repositories context handles repository management.
  Repositories belong to organizations and have a unique handle within each organization.
  """

  import Ecto.Query

  alias Micelio.Accounts
  alias Micelio.Accounts.OrganizationMembership
  alias Micelio.Audit
  alias Micelio.Forges
  alias Micelio.Mic.Seed
  alias Micelio.Repo

  alias Micelio.Repositories.{
    AccessTokens,
    Repository,
    RepositoryAccessToken,
    RepositoryInteraction
  }

  alias Micelio.Storage

  @micelio_workspace_email "micelio@micelio.dev"
  @micelio_workspace_org_handle "micelio"
  @micelio_workspace_org_name "Micelio"
  @micelio_workspace_repository_handle "micelio"
  @micelio_workspace_repository_name "Micelio"
  @micelio_workspace_repository_description "The Micelio platform"
  @micelio_workspace_repository_url "https://micelio.dev"
  @micelio_workspace_repository_visibility "public"
  @micelio_workspace_lock_key :erlang.phash2("micelio_workspace")
  @max_account_handle_length 39
  @max_repository_handle_length 100

  @doc """
  Gets a repository by ID.
  """
  def get_repository(id), do: Repo.get(Repository, id)

  @doc """
  Gets a repository by ID with organization preloaded.
  """
  def get_repository_with_organization(id) do
    Repository
    |> Repo.get(id)
    |> Repo.preload(organization: :account)
  end

  @doc """
  Preloads fork origin details for a repository.
  """
  def preload_fork_origin(%Repository{} = repository) do
    Repo.preload(repository, forked_from: [organization: :account])
  end

  @doc """
  Gets a repository by organization ID and handle (case-insensitive).
  """
  def get_repository_by_handle(organization_id, handle) do
    Repository
    |> where([p], p.organization_id == ^organization_id)
    |> where([p], fragment("lower(?)", p.handle) == ^String.downcase(handle))
    |> Repo.one()
  end

  @doc """
  Gets a repository by forge host/owner/repo reference (case-insensitive).
  """
  def get_repository_by_forge_reference(forge_host, forge_owner, forge_repo) do
    host = String.downcase(String.trim(forge_host))
    owner = String.downcase(String.trim(forge_owner))
    repo = String.downcase(String.trim(forge_repo))

    Repository
    |> where([r], fragment("lower(?)", r.forge_host) == ^host)
    |> where([r], fragment("lower(?)", r.forge_owner) == ^owner)
    |> where([r], fragment("lower(?)", r.forge_repo) == ^repo)
    |> Repo.one()
  end

  @doc """
  Resolves an external forge reference to a mirrored repository.

  If a repository mirror does not exist yet, it is created lazily from forge metadata.
  """
  def get_or_create_repository_for_forge_reference(user, forge_host, forge_owner, forge_repo)
      when is_binary(forge_host) and is_binary(forge_owner) and is_binary(forge_repo) do
    with {:ok, provider} <- Forges.provider_for_host(forge_host),
         {:ok, metadata} <-
           Forges.fetch_repository(provider,
             owner: forge_owner,
             repo: forge_repo,
             access_token: oauth_access_token(user, provider)
           ) do
      upsert_forge_repository(user, metadata)
    else
      {:error, :provider_not_supported} ->
        {:error, :not_found}

      {:error, :access_denied} ->
        {:error, :integration_required}

      {:error, :not_found} ->
        {:error, :not_found}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Lists all repositories for an organization.
  """
  def list_repositories_for_organization(organization_id) do
    Repository
    |> where([p], p.organization_id == ^organization_id)
    |> order_by([p], asc: p.name)
    |> Repo.all()
  end

  @doc """
  Lists public repositories for an organization.
  """
  def list_public_repositories_for_organization(organization_id) do
    list_public_repositories_for_organizations([organization_id])
  end

  @doc """
  Lists public repositories for a set of organization IDs.
  """
  def list_public_repositories_for_organizations([]), do: []

  def list_public_repositories_for_organizations(organization_ids) do
    Repository
    |> where([p], p.organization_id in ^organization_ids and p.visibility == "public")
    |> join(:left, [p], o in assoc(p, :organization))
    |> join(:left, [p, o], a in assoc(o, :account))
    |> preload([_p, o, a], organization: {o, account: a})
    |> order_by([_p, _o, a], asc: a.handle)
    |> order_by([p], asc: p.name)
    |> Repo.all()
  end

  @doc """
  Lists popular public repositories ordered by recency.
  """
  def list_popular_repositories(opts \\ []) do
    limit = Keyword.get(opts, :limit, 6)
    offset = Keyword.get(opts, :offset, 0)

    Repository
    |> where([p], p.visibility == "public")
    |> join(:left, [p], o in assoc(p, :organization))
    |> join(:left, [p, o], a in assoc(o, :account))
    |> preload([_p, o, a], organization: {o, account: a})
    |> order_by([p, _o, a], desc: p.inserted_at, asc: a.handle, asc: p.name)
    |> limit(^limit)
    |> offset(^offset)
    |> Repo.all()
  end

  @doc """
  Lists repositories a user has recently interacted with, ordered by latest interaction.
  """
  def list_recent_repositories_for_user(%Accounts.User{} = user, opts \\ []) do
    limit = Keyword.get(opts, :limit, 6)
    offset = Keyword.get(opts, :offset, 0)

    Repository
    |> join(:inner, [p], pi in RepositoryInteraction,
      on: pi.repository_id == p.id and pi.user_id == ^user.id
    )
    |> join(:left, [p, _pi], o in assoc(p, :organization))
    |> join(:left, [p, _pi, o], a in assoc(o, :account))
    |> preload([_p, _pi, o, a], organization: {o, account: a})
    |> group_by([p, _pi, o, a], [p.id, o.id, a.id])
    |> order_by([_p, pi, _o, _a], desc: max(pi.last_interacted_at))
    |> limit(^limit)
    |> offset(^offset)
    |> Repo.all()
  end

  @doc """
  Records a repository interaction for a user.
  """
  def record_repository_interaction(%Accounts.User{} = user, %Repository{} = repository, type)
      when is_binary(type) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    Repo.insert(
      %RepositoryInteraction{
        user_id: user.id,
        repository_id: repository.id,
        last_interacted_at: now,
        interaction_count: 1,
        last_interaction_type: type
      },
      on_conflict: [
        set: [
          last_interacted_at: now,
          last_interaction_type: type,
          updated_at: now
        ],
        inc: [interaction_count: 1]
      ],
      conflict_target: [:user_id, :repository_id]
    )
  end

  def record_repository_interaction(_, _, _), do: {:error, :invalid_interaction}

  @doc """
  Lists repositories for mobile clients with pagination and optional sync filtering.
  """
  def list_mobile_repositories(opts \\ []) do
    user = Keyword.get(opts, :user)
    limit = Keyword.get(opts, :limit, 20)
    offset = Keyword.get(opts, :offset, 0)
    updated_since = Keyword.get(opts, :updated_since)

    Repository
    |> mobile_visibility_filter(user)
    |> maybe_filter_updated_since(updated_since)
    |> join(:left, [p], o in assoc(p, :organization))
    |> join(:left, [p, o], a in assoc(o, :account))
    |> preload([_p, o, a], organization: {o, account: a})
    |> order_by([p, _o, a], desc: p.updated_at, asc: a.handle, asc: p.name)
    |> limit(^limit)
    |> offset(^offset)
    |> Repo.all()
  end

  @doc """
  Lists all repositories.
  """
  def list_repositories do
    Repo.all(Repository)
  end

  @doc """
  Creates a repository access token.
  """
  def create_repository_access_token(%Repository{} = repository, %Accounts.User{} = user, attrs) do
    AccessTokens.create(repository, user, attrs)
  end

  @doc """
  Lists repository access tokens.
  """
  def list_repository_access_tokens(%Repository{} = repository) do
    AccessTokens.list_for_repository(repository.id)
  end

  @doc """
  Revokes a repository access token.
  """
  def revoke_repository_access_token(%RepositoryAccessToken{} = token) do
    AccessTokens.revoke(token)
  end

  @doc """
  Ensures the Micelio workspace repository exists with default metadata.
  """
  def ensure_micelio_workspace do
    Repo.transaction(fn ->
      lock_micelio_workspace!()

      with {:ok, user} <- Accounts.get_or_create_user_by_email(@micelio_workspace_email),
           {:ok, organization} <- ensure_micelio_organization(),
           {:ok, _membership} <- ensure_micelio_membership(user, organization),
           {:ok, repository} <- ensure_micelio_project(organization) do
        %{user: user, organization: organization, repository: repository}
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
    |> case do
      {:ok, data} -> {:ok, data}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Seeds the Micelio workspace storage from a local path.
  """
  def seed_micelio_workspace(root_path, opts \\ []) when is_binary(root_path) do
    with {:ok, %{repository: repository} = data} <- ensure_micelio_workspace() do
      case Seed.seed_repository_from_path(repository.id, root_path, opts) do
        {:ok, seed_result} -> {:ok, Map.merge(data, seed_result)}
        {:error, :already_seeded} -> {:ok, Map.put(data, :already_seeded, true)}
        {:error, reason} -> {:error, reason}
      end
    end
  end

  @doc """
  Seeds the Micelio workspace if a source path is configured or provided.
  """
  def seed_micelio_workspace_if_configured(opts \\ []) do
    seed_opts = Keyword.get(opts, :seed_opts, [])
    repository = Keyword.get(opts, :repository)

    case workspace_path_from_opts(opts) do
      nil ->
        {:ok, :skipped}

      path ->
        seed_micelio_workspace_with_repository(repository, path, seed_opts)
    end
  end

  @doc """
  Searches repositories by name and description using full-text search.
  """
  def search_repositories(raw_query, opts \\ []) do
    query = normalize_search_query(raw_query)

    if query == "" do
      []
    else
      user = Keyword.get(opts, :user)
      limit = Keyword.get(opts, :limit, 50)
      # Convert the query to a tsquery format for PostgreSQL full-text search
      tsquery = query |> String.split() |> Enum.join(" & ")

      Repository
      |> where([p], fragment("search_vector @@ to_tsquery('english', ?)", ^tsquery))
      |> search_visibility_filter(user)
      |> join(:left, [p], o in assoc(p, :organization))
      |> join(:left, [p, o], a in assoc(o, :account))
      |> preload([_p, o, a], organization: {o, account: a})
      |> order_by(
        [p],
        fragment("ts_rank(search_vector, to_tsquery('english', ?)) DESC", ^tsquery)
      )
      |> limit(^limit)
      |> Repo.all()
    end
  end

  @doc """
  Lists all repositories for the organizations a user belongs to.
  Repositories are ordered by organization handle and repository name.
  """
  def list_repositories_for_user(user) do
    organization_ids =
      user
      |> Accounts.list_organizations_for_user()
      |> Enum.map(& &1.id)

    list_repositories_for_organizations(organization_ids)
  end

  @doc """
  Lists all repositories for a set of organization IDs.
  """
  def list_repositories_for_organizations([]), do: []

  def list_repositories_for_organizations(organization_ids) do
    Repository
    |> where([p], p.organization_id in ^organization_ids)
    |> join(:left, [p], o in assoc(p, :organization))
    |> join(:left, [p, o], a in assoc(o, :account))
    |> preload([p, o, a], organization: {o, account: a})
    |> order_by([_p, _o, a], asc: a.handle)
    |> order_by([p], asc: p.name)
    |> Repo.all()
  end

  @doc """
  Creates a new repository.
  """
  def create_repository(attrs, opts \\ []) do
    Repo.transaction(fn ->
      case enforce_repository_limit(attrs) do
        :ok ->
          case %Repository{}
               |> Repository.changeset(attrs)
               |> Repo.insert() do
            {:ok, repository} ->
              case Audit.log_repository_action(repository, "repository.created",
                     user: Keyword.get(opts, :user),
                     metadata: repository_audit_metadata(repository)
                   ) do
                {:ok, _log} -> repository
                {:error, changeset} -> Repo.rollback(changeset)
              end

            {:error, changeset} ->
              Repo.rollback(changeset)
          end

        {:error, changeset} ->
          Repo.rollback(changeset)
      end
    end)
    |> normalize_transaction_result()
  end

  @doc """
  Forks a repository into a new organization, copying storage and tracking origin.
  """
  def fork_repository(
        %Repository{} = source,
        %Accounts.Organization{} = organization,
        attrs \\ %{},
        opts \\ []
      ) do
    attrs = normalize_fork_attrs(source, organization, attrs)

    Repo.transaction(fn ->
      case enforce_repository_limit(attrs) do
        :ok ->
          case create_fork_repository(source, attrs, organization) do
            {:ok, repository} ->
              case copy_repository_storage(source.id, repository.id) do
                :ok ->
                  case Audit.log_repository_action(repository, "repository.forked",
                         user: Keyword.get(opts, :user),
                         metadata: %{forked_from_id: source.id}
                       ) do
                    {:ok, _log} -> repository
                    {:error, changeset} -> Repo.rollback(changeset)
                  end

                {:error, reason} ->
                  Repo.rollback(reason)
              end

            {:error, changeset} ->
              Repo.rollback(changeset)
          end

        {:error, changeset} ->
          Repo.rollback(changeset)
      end
    end)
    |> case do
      {:ok, repository} -> {:ok, repository}
      {:error, %Ecto.Changeset{} = changeset} -> {:error, changeset}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Updates a repository.
  """
  def update_repository(%Repository{} = repository, attrs, opts \\ []) do
    changeset = Repository.changeset(repository, attrs)
    update_repository_with_audit(repository, changeset, "repository.updated", opts)
  end

  @doc """
  Updates repository settings (name, description, visibility).
  """
  def update_repository_settings(%Repository{} = repository, attrs, opts \\ []) do
    changeset = Repository.settings_changeset(repository, attrs)
    update_repository_with_audit(repository, changeset, "repository.settings_updated", opts)
  end

  @doc """
  Deletes a repository.
  """
  def delete_repository(%Repository{} = repository, opts \\ []) do
    Repo.transaction(fn ->
      case Audit.log_repository_action(repository, "repository.deleted",
             user: Keyword.get(opts, :user),
             metadata: repository_audit_metadata(repository)
           ) do
        {:ok, _log} ->
          case Repo.delete(repository) do
            {:ok, deleted} -> deleted
            {:error, changeset} -> Repo.rollback(changeset)
          end

        {:error, changeset} ->
          Repo.rollback(changeset)
      end
    end)
    |> normalize_transaction_result()
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking project changes.
  """
  def change_repository(%Repository{} = repository, attrs \\ %{}, _opts \\ []) do
    Repository.changeset(repository, attrs)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for repository settings changes.
  """
  def change_repository_settings(%Repository{} = repository, attrs \\ %{}, _opts \\ []) do
    Repository.settings_changeset(repository, attrs)
  end

  @doc """
  Checks if a handle is available for a given organization.
  """
  def handle_available?(organization_id, handle) do
    is_nil(get_repository_by_handle(organization_id, handle))
  end

  @doc """
  Gets a repository by organization handle and project handle for a user.
  """
  def get_repository_for_user_by_handle(user, organization_handle, repository_handle) do
    with {:ok, organization} <- Accounts.get_organization_by_handle(organization_handle),
         %Repository{} = repository <-
           get_repository_by_handle(organization.id, repository_handle) do
      cond do
        repository.visibility == "public" ->
          {:ok, repository, organization}

        user_in_organization?(user, organization.id) ->
          {:ok, repository, organization}

        true ->
          {:error, :unauthorized}
      end
    else
      nil -> {:error, :not_found}
      {:error, :not_found} -> {:error, :not_found}
    end
  end

  defp user_in_organization?(%Accounts.User{} = user, organization_id),
    do: Accounts.user_in_organization?(user, organization_id)

  defp user_in_organization?(_, _), do: false

  defp oauth_access_token(%Accounts.User{} = user, provider)
       when provider in ["github", "gitlab"] do
    provider_atom =
      case provider do
        "github" -> :github
        "gitlab" -> :gitlab
      end

    case Accounts.get_oauth_identity_for_user(user, provider_atom) do
      %{access_token_encrypted: token} when is_binary(token) and token != "" -> token
      _ -> nil
    end
  end

  defp oauth_access_token(_, _provider), do: nil

  defp upsert_forge_repository(%Accounts.User{} = user, metadata) do
    Repo.transaction(fn ->
      case get_repository_by_forge_reference(
             metadata.forge_host,
             metadata.forge_owner,
             metadata.forge_repo
           ) do
        %Repository{} = existing ->
          ensure_repository_access(existing, user)
          |> case do
            :ok -> preload_repository_with_organization(existing)
            {:error, reason} -> Repo.rollback(reason)
          end

        nil ->
          with {:ok, organization} <- ensure_forge_organization(user, metadata),
               :ok <- ensure_forge_membership(user, organization),
               attrs = forge_repository_attrs(metadata, organization.id),
               attrs = ensure_unique_repository_handle(attrs),
               {:ok, repository} <- create_repository(attrs, user: user) do
            preload_repository_with_organization(repository)
          else
            {:error, reason} -> Repo.rollback(reason)
          end
      end
    end)
    |> normalize_transaction_result()
  end

  defp ensure_repository_access(%Repository{visibility: "public"}, _user), do: :ok

  defp ensure_repository_access(%Repository{} = repository, %Accounts.User{} = user) do
    if user_in_organization?(user, repository.organization_id) do
      :ok
    else
      {:error, :integration_required}
    end
  end

  defp ensure_repository_access(_repository, _user), do: {:error, :integration_required}

  defp ensure_forge_organization(%Accounts.User{} = user, metadata) do
    handle = forge_account_handle(metadata.forge_provider, metadata.forge_owner)
    display_name = "#{metadata.forge_owner} (#{String.capitalize(metadata.forge_provider)})"

    case Accounts.get_organization_by_handle(handle) do
      {:ok, organization} ->
        {:ok, organization}

      {:error, :not_found} ->
        Accounts.create_organization_for_user(
          user,
          %{handle: handle, name: display_name},
          allow_reserved: true
        )
    end
  end

  defp ensure_forge_membership(%Accounts.User{} = user, organization) do
    if Accounts.user_in_organization?(user, organization.id) do
      :ok
    else
      case Accounts.create_organization_membership(%{
             user_id: user.id,
             organization_id: organization.id,
             role: :admin
           }) do
        {:ok, _membership} -> :ok
        {:error, reason} -> {:error, reason}
      end
    end
  end

  defp forge_repository_attrs(metadata, organization_id) do
    %{
      handle: forge_repository_handle(metadata.forge_repo),
      name: metadata.name,
      description: metadata.description,
      url: metadata.url,
      visibility: metadata.visibility,
      organization_id: organization_id,
      forge_provider: metadata.forge_provider,
      forge_host: metadata.forge_host,
      forge_owner: metadata.forge_owner,
      forge_repo: metadata.forge_repo,
      forge_external_id: metadata.forge_external_id,
      forge_default_branch: metadata.forge_default_branch,
      mirror_status: "pending"
    }
  end

  defp ensure_unique_repository_handle(attrs) do
    organization_id = Map.fetch!(attrs, :organization_id)
    base_handle = Map.fetch!(attrs, :handle)

    if handle_available?(organization_id, base_handle) do
      attrs
    else
      suffix =
        attrs
        |> Map.get(:forge_repo, "")
        |> :erlang.phash2()
        |> Integer.to_string(16)
        |> String.slice(0, 6)

      candidate =
        "#{base_handle}-#{suffix}"
        |> String.slice(0, @max_repository_handle_length)

      Map.put(attrs, :handle, candidate)
    end
  end

  defp preload_repository_with_organization(%Repository{} = repository) do
    repository
    |> Repo.preload(organization: :account)
  end

  defp forge_account_handle(provider, owner) do
    suffix = normalize_slug(owner)
    base = "#{provider}-#{suffix}"
    String.slice(base, 0, @max_account_handle_length)
  end

  defp forge_repository_handle(repo) do
    repo
    |> normalize_slug()
    |> String.slice(0, @max_repository_handle_length)
  end

  defp normalize_slug(value) when is_binary(value) do
    normalized =
      value
      |> String.downcase()
      |> String.replace(~r/[^a-z0-9]+/u, "-")
      |> String.trim("-")

    if normalized == "", do: "repo", else: normalized
  end

  defp normalize_slug(_value), do: "repo"

  defp lock_micelio_workspace! do
    Repo.query!("SELECT pg_advisory_xact_lock($1)", [@micelio_workspace_lock_key])
    :ok
  end

  defp ensure_micelio_organization do
    case Accounts.get_organization_by_handle(@micelio_workspace_org_handle) do
      {:ok, organization} ->
        {:ok, organization}

      {:error, :not_found} ->
        Accounts.create_organization(
          %{
            handle: @micelio_workspace_org_handle,
            name: @micelio_workspace_org_name
          },
          allow_reserved: true
        )
    end
  end

  defp ensure_micelio_membership(%Accounts.User{} = user, %Accounts.Organization{} = organization) do
    case Repo.get_by(OrganizationMembership,
           user_id: user.id,
           organization_id: organization.id
         ) do
      nil ->
        Accounts.create_organization_membership(%{
          user_id: user.id,
          organization_id: organization.id,
          role: :admin
        })

      %OrganizationMembership{} = membership ->
        {:ok, membership}
    end
  end

  defp ensure_micelio_project(%Accounts.Organization{} = organization) do
    attrs = %{
      handle: @micelio_workspace_repository_handle,
      name: @micelio_workspace_repository_name,
      description: @micelio_workspace_repository_description,
      url: @micelio_workspace_repository_url,
      visibility: @micelio_workspace_repository_visibility,
      organization_id: organization.id
    }

    case get_repository_by_handle(organization.id, @micelio_workspace_repository_handle) do
      nil ->
        create_repository(attrs)

      %Repository{} = repository ->
        update_attrs =
          Enum.reduce([:description, :url], %{}, fn key, acc ->
            value = Map.get(repository, key)
            desired = Map.get(attrs, key)

            if value in [nil, ""], do: Map.put(acc, key, desired), else: acc
          end)

        update_attrs =
          if repository.visibility == @micelio_workspace_repository_visibility do
            update_attrs
          else
            Map.put(update_attrs, :visibility, @micelio_workspace_repository_visibility)
          end

        if update_attrs == %{} do
          {:ok, repository}
        else
          update_repository(repository, update_attrs)
        end
    end
  end

  defp seed_micelio_workspace_with_repository(nil, path, seed_opts) do
    seed_micelio_workspace(path, seed_opts)
  end

  defp seed_micelio_workspace_with_repository(%Repository{} = repository, path, seed_opts) do
    case Seed.seed_repository_from_path(repository.id, path, seed_opts) do
      {:ok, seed_result} -> {:ok, Map.merge(%{repository: repository}, seed_result)}
      {:error, :already_seeded} -> {:ok, %{repository: repository, already_seeded: true}}
      {:error, reason} -> {:error, reason}
    end
  end

  defp workspace_path_from_opts(opts) do
    case Keyword.get(opts, :path, Application.get_env(:micelio, :micelio_workspace_path)) do
      path when is_binary(path) ->
        trimmed = String.trim(path)
        if trimmed != "", do: trimmed

      _ ->
        nil
    end
  end

  defp normalize_search_query(query) when is_binary(query) do
    tokens =
      query
      |> String.downcase()
      |> then(&Regex.scan(~r/[[:alnum:]]+/u, &1))
      |> List.flatten()

    case tokens do
      [] -> ""
      _ -> tokens |> Enum.map_join(" AND ", &"#{&1}*")
    end
  end

  defp normalize_search_query(_), do: ""

  defp normalize_fork_attrs(
         %Repository{} = source,
         %Accounts.Organization{} = organization,
         attrs
       ) do
    attrs =
      attrs
      |> Map.new(fn {key, value} -> {to_string(key), value} end)
      |> Map.put_new("handle", source.handle)
      |> Map.put_new("name", source.name)
      |> Map.put_new("description", source.description)
      |> Map.put_new("url", source.url)
      |> Map.put_new("visibility", source.visibility)
      |> Map.put("organization_id", organization.id)

    attrs
  end

  defp create_fork_repository(%Repository{} = source, attrs, _organization) do
    %Repository{}
    |> Repository.changeset(attrs)
    |> Ecto.Changeset.put_change(:forked_from_id, source.id)
    |> Repo.insert()
  end

  defp copy_repository_storage(source_id, target_id) do
    source_prefix = repository_storage_prefix(source_id)
    target_prefix = repository_storage_prefix(target_id)

    with {:ok, keys} <- Storage.list(source_prefix) do
      Enum.reduce_while(keys, :ok, fn key, :ok ->
        target_key = String.replace_prefix(key, source_prefix, target_prefix)

        with {:ok, content} <- Storage.get(key),
             {:ok, _} <- Storage.put(target_key, content) do
          {:cont, :ok}
        else
          {:error, reason} -> {:halt, {:error, reason}}
        end
      end)
    end
  end

  defp repository_storage_prefix(repository_id), do: "repositories/#{repository_id}"

  defp search_visibility_filter(query, %Accounts.User{} = user) do
    organization_ids =
      user
      |> Accounts.list_organizations_for_user()
      |> Enum.map(& &1.id)

    if organization_ids == [] do
      where(query, [p, _f], p.visibility == "public")
    else
      where(
        query,
        [p, _f],
        p.visibility == "public" or p.organization_id in ^organization_ids
      )
    end
  end

  defp search_visibility_filter(query, _user) do
    where(query, [p, _f], p.visibility == "public")
  end

  defp mobile_visibility_filter(query, %Accounts.User{} = user) do
    organization_ids =
      user
      |> Accounts.list_organizations_for_user()
      |> Enum.map(& &1.id)

    if organization_ids == [] do
      where(query, [p], p.visibility == "public")
    else
      where(query, [p], p.visibility == "public" or p.organization_id in ^organization_ids)
    end
  end

  defp mobile_visibility_filter(query, _user) do
    where(query, [p], p.visibility == "public")
  end

  defp maybe_filter_updated_since(query, nil), do: query

  defp maybe_filter_updated_since(query, %DateTime{} = updated_since) do
    where(query, [p], p.updated_at > ^updated_since)
  end

  defp update_repository_with_audit(%Repository{} = _project, changeset, action, opts) do
    Repo.transaction(fn ->
      case Repo.update(changeset) do
        {:ok, updated} ->
          if changeset.changes == %{} do
            updated
          else
            case Audit.log_repository_action(updated, action,
                   user: Keyword.get(opts, :user),
                   metadata: %{changes: changeset.changes}
                 ) do
              {:ok, _log} -> updated
              {:error, changeset} -> Repo.rollback(changeset)
            end
          end

        {:error, changeset} ->
          Repo.rollback(changeset)
      end
    end)
    |> normalize_transaction_result()
  end

  defp repository_audit_metadata(%Repository{} = repository) do
    %{
      handle: repository.handle,
      name: repository.name,
      visibility: repository.visibility,
      organization_id: repository.organization_id
    }
  end

  defp enforce_repository_limit(attrs) do
    case max_repositories_per_tenant() do
      :unlimited ->
        :ok

      limit ->
        organization_id = Map.get(attrs, :organization_id) || Map.get(attrs, "organization_id")

        if is_nil(organization_id) do
          :ok
        else
          existing_count =
            Repository
            |> where([p], p.organization_id == ^organization_id)
            |> Repo.aggregate(:count, :id)

          if existing_count >= limit do
            changeset =
              %Repository{}
              |> Repository.changeset(attrs)
              |> Ecto.Changeset.add_error(
                :base,
                "project limit reached for this organization"
              )

            {:error, changeset}
          else
            :ok
          end
        end
    end
  end

  defp max_repositories_per_tenant do
    :micelio
    |> Application.get_env(:repository_limits, [])
    |> Keyword.get(:max_repositories_per_tenant, 25)
    |> normalize_repository_limit()
  end

  defp normalize_repository_limit(:unlimited), do: :unlimited
  defp normalize_repository_limit(:infinity), do: :unlimited
  defp normalize_repository_limit(nil), do: :unlimited

  defp normalize_repository_limit(limit) when is_integer(limit) and limit >= 0, do: limit
  defp normalize_repository_limit(_limit), do: :unlimited

  defp normalize_transaction_result({:ok, result}), do: {:ok, result}

  defp normalize_transaction_result({:error, %Ecto.Changeset{} = changeset}),
    do: {:error, changeset}

  defp normalize_transaction_result({:error, reason}), do: {:error, reason}
end
