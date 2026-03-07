defmodule Micelio.Storage do
  @moduledoc """
  Storage abstraction for session files and artifacts.

  By default uses local filesystem storage. Can be configured to use S3 or the
  tiered cache backend.

  Configuration via `config/runtime.exs`:
      STORAGE_BACKEND=local|s3|tiered
      STORAGE_LOCAL_PATH=/var/micelio/storage  # defaults to /var/micelio/storage in prod or <tmp>/micelio/storage in dev/test
      S3_BUCKET=micelio-sessions
      S3_REGION=us-east-1
      STORAGE_CACHE_PATH=/var/micelio/cache
      STORAGE_CDN_BASE_URL=https://cdn.example.com/micelio
  """

  alias Micelio.Audit
  alias Micelio.Repo
  alias Micelio.Repositories.Repository
  alias Micelio.Storage.S3Config
  alias Micelio.Storage.S3Validator

  require Logger

  @type user_ref :: Micelio.Accounts.User.t() | Ecto.UUID.t() | nil

  @callback put(user_ref(), String.t(), binary()) :: {:ok, String.t()} | {:error, term()}
  @callback get(user_ref(), String.t()) :: {:ok, binary()} | {:error, term()}
  @callback delete(user_ref(), String.t()) :: {:ok, String.t()} | {:error, term()}
  @callback url(user_ref(), String.t()) :: String.t() | nil

  @doc """
  Stores a file and returns its key/path.
  """
  def put(key, content) do
    put(key, content, [])
  end

  def put(key, content, opts) when is_binary(key) and is_list(opts) do
    {scoped_key, scoped_opts} = scope_repository_storage(key, opts)
    call_backend(:put, [scoped_key, content], scoped_opts)
  end

  @doc """
  Stores a file using user-scoped storage when available.
  """
  def put(user, key, content) when is_binary(key) do
    Micelio.Storage.UserS3.put(user, key, content)
  end

  def put(user, key, content, opts) do
    Micelio.Storage.UserS3.put(user, key, content, opts)
  end

  @doc """
  Retrieves a file by key.
  """
  def get(key) do
    get(key, [])
  end

  def get(key, opts) when is_binary(key) and is_list(opts) do
    {scoped_key, scoped_opts} = scope_repository_storage(key, opts)
    call_backend(:get, [scoped_key], scoped_opts)
  end

  @doc """
  Retrieves a file using user-scoped storage when available.
  """
  def get(user, key) when is_binary(key) do
    Micelio.Storage.UserS3.get(user, key)
  end

  def get(user, key, opts) do
    Micelio.Storage.UserS3.get(user, key, opts)
  end

  @doc """
  Retrieves a file with storage metadata (e.g., ETag).
  """
  def get_with_metadata(key) do
    get_with_metadata(key, [])
  end

  def get_with_metadata(key, opts) do
    {scoped_key, scoped_opts} = scope_repository_storage(key, opts)
    call_backend(:get_with_metadata, [scoped_key], scoped_opts)
  end

  @doc """
  Deletes a file by key.
  """
  def delete(key) do
    delete(key, [])
  end

  def delete(key, opts) when is_binary(key) and is_list(opts) do
    {scoped_key, scoped_opts} = scope_repository_storage(key, opts)
    call_backend(:delete, [scoped_key], scoped_opts)
  end

  @doc """
  Deletes a file using user-scoped storage when available.
  """
  def delete(user, key) when is_binary(key) do
    Micelio.Storage.UserS3.delete(user, key)
  end

  def delete(user, key, opts) do
    Micelio.Storage.UserS3.delete(user, key, opts)
  end

  @doc """
  Lists files with a given prefix.
  """
  def list(prefix) do
    list(prefix, [])
  end

  def list(prefix, opts) do
    {scoped_prefix, scoped_opts} = scope_repository_storage(prefix, opts)
    call_backend(:list, [scoped_prefix], scoped_opts)
  end

  @doc """
  Checks if a file exists.
  """
  def exists?(key) do
    exists?(key, [])
  end

  def exists?(key, opts) do
    {scoped_key, scoped_opts} = scope_repository_storage(key, opts)
    call_backend(:exists?, [scoped_key], scoped_opts)
  end

  @doc """
  Returns a CDN URL for the given key when configured.

  Returns nil when no CDN base URL is configured.
  """
  def cdn_url(key) when is_binary(key) do
    cdn_url(key, [])
  end

  def cdn_url(key, opts) when is_binary(key) do
    {scoped_key, scoped_opts} = scope_repository_storage(key, opts)
    config = storage_config(scoped_opts)

    case Keyword.get(config, :cdn_base_url) do
      base when is_binary(base) and base != "" ->
        base = String.trim_trailing(base, "/")
        "#{base}/#{encode_cdn_key(scoped_key)}"

      _ ->
        nil
    end
  end

  @doc """
  Returns metadata for a key when available (e.g., ETag).
  """
  def head(key) do
    head(key, [])
  end

  def head(key, opts) do
    {scoped_key, scoped_opts} = scope_repository_storage(key, opts)
    call_backend(:head, [scoped_key], scoped_opts)
  end

  @doc """
  Stores a file only if the current ETag matches.
  """
  def put_if_match(key, content, etag) do
    put_if_match(key, content, etag, [])
  end

  def put_if_match(key, content, etag, opts) do
    {scoped_key, scoped_opts} = scope_repository_storage(key, opts)
    call_backend(:put_if_match, [scoped_key, content, etag], scoped_opts)
  end

  @doc """
  Stores a file only if it does not already exist.
  """
  def put_if_none_match(key, content) do
    put_if_none_match(key, content, [])
  end

  def put_if_none_match(key, content, opts) do
    {scoped_key, scoped_opts} = scope_repository_storage(key, opts)
    call_backend(:put_if_none_match, [scoped_key, content], scoped_opts)
  end

  @doc """
  Builds a URL for a storage key using user-scoped storage when available.
  """
  def url(user, key) do
    Micelio.Storage.UserS3.url(user, key)
  end

  @doc """
  Returns a user's S3 configuration, if one exists.
  """
  def get_user_s3_config(%Micelio.Accounts.User{id: user_id}) when is_binary(user_id) do
    get_user_s3_config(user_id)
  end

  def get_user_s3_config(user_id) when is_binary(user_id) do
    Repo.get_by(S3Config, user_id: user_id)
  end

  @doc """
  Returns a changeset for editing a user's S3 configuration.
  """
  def change_user_s3_config(user_or_config, attrs \\ %{})

  def change_user_s3_config(%Micelio.Accounts.User{} = user, attrs) do
    config = get_user_s3_config(user) || %S3Config{user_id: user.id}
    change_user_s3_config(config, attrs)
  end

  def change_user_s3_config(%S3Config{} = config, attrs) do
    config_for_form =
      if attrs == %{} do
        %{config | access_key_id: nil, secret_access_key: nil}
      else
        config
      end

    S3Config.user_changeset(config_for_form, attrs)
  end

  @doc """
  Returns a changeset for validating a user's S3 configuration.
  """
  def user_s3_changeset(user_or_config, attrs \\ %{})

  def user_s3_changeset(%Micelio.Accounts.User{} = user, attrs) do
    config = get_user_s3_config(user) || %S3Config{user_id: user.id}
    user_s3_changeset(config, attrs)
  end

  def user_s3_changeset(%S3Config{} = config, attrs) do
    attrs = prepare_user_s3_attrs(config, attrs)
    S3Config.user_changeset(config, attrs)
  end

  @doc """
  Validates a user's S3 configuration without persisting it.
  """
  def validate_user_s3_config(%Micelio.Accounts.User{} = user, attrs) do
    validate_user_s3_config(user, attrs, validator: s3_validator_module())
  end

  def validate_user_s3_config(%Micelio.Accounts.User{} = user, attrs, opts) do
    config = get_user_s3_config(user) || %S3Config{user_id: user.id}
    attrs = prepare_user_s3_attrs(config, attrs)
    changeset = S3Config.user_changeset(config, attrs)

    if changeset.valid? do
      case allow_s3_validation?(user.id, opts) do
        :ok ->
          updated = Ecto.Changeset.apply_changes(changeset)
          validator = Keyword.get(opts, :validator, s3_validator_module())
          run_s3_validator(validator, updated, opts)

        {:error, result} ->
          {:error, result}
      end
    else
      {:error, changeset}
    end
  end

  @doc """
  Creates or updates a user's S3 configuration and validates it.
  """
  def upsert_user_s3_config(%Micelio.Accounts.User{} = user, attrs) do
    upsert_user_s3_config(user, attrs, validator: s3_validator_module())
  end

  def upsert_user_s3_config(%Micelio.Accounts.User{} = user, attrs, opts) do
    config = get_user_s3_config(user) || %S3Config{user_id: user.id}
    attrs = prepare_user_s3_attrs(config, attrs)

    changeset =
      config
      |> S3Config.user_changeset(attrs)
      |> reset_validation_fields()

    case Repo.insert_or_update(changeset) do
      {:ok, saved} ->
        validator = Keyword.get(opts, :validator, s3_validator_module())
        {updated, result} = validate_and_update(saved, validator, user, opts)
        log_s3_config_audit(user, config, updated)
        {:ok, updated, result}

      {:error, changeset} ->
        {:error, changeset}
    end
  end

  @doc """
  Deletes a user's S3 configuration.
  """
  def delete_user_s3_config(%Micelio.Accounts.User{} = user) do
    case get_user_s3_config(user) do
      nil ->
        {:ok, nil}

      %S3Config{} = config ->
        with {:ok, deleted} <- Repo.delete(config) do
          log_s3_config_deleted(user, config)
          {:ok, deleted}
        end
    end
  end

  defp call_backend(fun, args, opts) do
    {backend, backend_opts} = backend_and_opts(opts)
    Code.ensure_loaded(backend)

    if function_exported?(backend, fun, length(args) + 1) do
      apply(backend, fun, args ++ [backend_opts])
    else
      apply(backend, fun, args)
    end
  end

  defp backend_and_opts(opts) do
    config = storage_config(opts)

    case Keyword.get(config, :backend, :local) do
      :local ->
        base_path = Keyword.get(config, :local_path, default_local_path())
        {Micelio.Storage.Local, Keyword.put(opts, :base_path, base_path)}

      :s3 ->
        {Micelio.Storage.S3, config}

      :tiered ->
        {Micelio.Storage.Tiered, config}
    end
  end

  defp storage_config(opts) do
    resolve_storage_config(opts)
  end

  defp resolve_storage_config(opts) do
    explicit_config = Keyword.get(opts, :storage_config)

    if explicit_config do
      explicit_config
    else
      default_config = Application.get_env(:micelio, __MODULE__, [])
      repository_from_opts(opts) |> maybe_override_storage_backend(default_config)
    end
  end

  defp maybe_override_storage_backend(nil, config), do: config

  defp maybe_override_storage_backend(%Repository{} = repository, config) when is_list(config) do
    case repository.storage_backend do
      "local" -> Keyword.put(config, :backend, :local)
      "s3" -> Keyword.put(config, :backend, :s3)
      "tiered" -> Keyword.put(config, :backend, :tiered)
      _ -> config
    end
  end

  defp repository_from_opts(opts) do
    opts
    |> Keyword.get(:repository, Keyword.get(opts, :repository_id))
    |> maybe_load_repository()
  end

  defp maybe_load_repository(%Repository{} = repository), do: repository

  defp maybe_load_repository(repository_id) when is_binary(repository_id) do
    case Ecto.UUID.cast(repository_id) do
      {:ok, uuid} -> Repo.get(Repository, uuid)
      _ -> nil
    end
  end

  defp maybe_load_repository(_), do: nil

  defp scope_repository_storage(key, opts) when is_binary(key) and is_list(opts) do
    repository = repository_for_key(key, opts)
    scoped_key = apply_repository_key_prefix(key, repository)

    scoped_opts =
      if Keyword.has_key?(opts, :repository) or Keyword.has_key?(opts, :repository_id) do
        opts
      else
        if repository do
          Keyword.put_new(opts, :repository, repository)
        else
          opts
        end
      end

    {scoped_key, scoped_opts}
  end

  defp apply_repository_key_prefix(key, %Repository{storage_key_prefix: prefix})
       when is_binary(prefix) and prefix != "" do
    Path.join([String.trim(prefix, "/"), String.trim_leading(key, "/")])
  end

  defp apply_repository_key_prefix(key, _), do: key

  defp repository_for_key(key, opts) when is_binary(key) and is_list(opts) do
    opts
    |> Keyword.get(:repository, Keyword.get(opts, :repository_id))
    |> maybe_load_repository()
    |> case do
      nil -> parse_repository_from_key(key)
      repository -> repository
    end
  end

  defp parse_repository_from_key(key) when is_binary(key) do
    trimmed_key = String.trim_leading(key, "/")

    with [prefix, repository_id | _] <- String.split(trimmed_key, "/"),
         true <- prefix in ["projects", "repositories"],
         {:ok, uuid} <- Ecto.UUID.cast(repository_id),
         %Repository{} = repository <- Repo.get(Repository, uuid) do
      repository
    else
      _ -> nil
    end
  end

  defp parse_repository_from_key(_), do: nil

  defp default_local_path do
    Path.join([System.tmp_dir!(), "micelio", "storage"])
  end

  defp encode_cdn_key(key) when is_binary(key) do
    key
    |> String.split("/", trim: false)
    |> Enum.map_join("/", fn segment ->
      URI.encode(segment, fn ch -> URI.char_unreserved?(ch) end)
    end)
  end

  defp normalize_attrs(attrs) do
    Map.new(attrs, fn
      {key, value} when is_atom(key) -> {Atom.to_string(key), value}
      {key, value} -> {key, value}
    end)
  end

  defp prepare_user_s3_attrs(%S3Config{} = config, attrs) do
    attrs
    |> normalize_attrs()
    |> Map.put("user_id", config.user_id)
    |> drop_blank_credentials(config)
  end

  defp drop_blank_credentials(attrs, %S3Config{id: nil}), do: attrs

  defp drop_blank_credentials(attrs, %S3Config{}) do
    attrs
    |> drop_blank_field("access_key_id")
    |> drop_blank_field("secret_access_key")
  end

  defp drop_blank_field(attrs, key) do
    case Map.fetch(attrs, key) do
      {:ok, value} when is_binary(value) ->
        if String.trim(value) == "" do
          Map.delete(attrs, key)
        else
          attrs
        end

      _ ->
        attrs
    end
  end

  defp reset_validation_fields(changeset) do
    if changeset.valid? do
      changeset
      |> Ecto.Changeset.put_change(:validated_at, nil)
      |> Ecto.Changeset.put_change(:last_error, nil)
    else
      changeset
    end
  end

  defp validate_and_update(%S3Config{} = config, validator, user, opts) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    case allow_s3_validation?(user.id, opts) do
      :ok ->
        case validator.validate(config) do
          {:ok, result} ->
            {:ok, updated} =
              config
              |> Ecto.Changeset.change(%{validated_at: now, last_error: nil})
              |> Repo.update()

            {updated, {:ok, result}}

          {:error, result} ->
            message = validation_error_message(result)

            {:ok, updated} =
              config
              |> Ecto.Changeset.change(%{validated_at: nil, last_error: message})
              |> Repo.update()

            {updated, {:error, result}}
        end

      {:error, result} ->
        {:ok, updated} =
          config
          |> Ecto.Changeset.change(%{
            validated_at: nil,
            last_error: validation_rate_limited_message()
          })
          |> Repo.update()

        {updated, {:error, result}}
    end
  end

  defp validation_error_message(%{errors: errors}) when is_list(errors) do
    errors
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.join(" ")
    |> String.slice(0, 500)
  end

  defp validation_error_message(result) do
    result
    |> inspect()
    |> String.slice(0, 500)
  end

  def s3_validator_module do
    Application.get_env(:micelio, __MODULE__, [])
    |> Keyword.get(:s3_validator, S3Validator)
  end

  defp run_s3_validator(validator, config, opts) do
    validator_opts = Keyword.delete(opts, :validator)

    if function_exported?(validator, :validate, 2) do
      validator.validate(config, validator_opts)
    else
      validator.validate(config)
    end
  end

  defp allow_s3_validation?(user_id, opts) when is_binary(user_id) do
    rate_limit = Keyword.get(opts, :rate_limit, s3_validation_rate_limit())

    case rate_limit do
      false ->
        :ok

      settings when is_list(settings) ->
        limit = Keyword.get(settings, :limit, 5)
        window_ms = Keyword.get(settings, :window_ms, 60_000)

        if is_integer(limit) and limit > 0 do
          key = "storage:s3_validation:user:#{user_id}"

          case Hammer.check_rate(key, window_ms, limit) do
            {:allow, _count} -> :ok
            {:deny, _limit} -> {:error, validation_rate_limited_result()}
          end
        else
          :ok
        end

      _ ->
        :ok
    end
  end

  defp s3_validation_rate_limit do
    :micelio
    |> Application.get_env(:s3_validation_rate_limit, [])
    |> Keyword.put_new(:limit, 5)
    |> Keyword.put_new(:window_ms, 60_000)
  end

  defp validation_rate_limited_result do
    %{
      ok?: false,
      errors: [validation_rate_limited_message()],
      steps: %{}
    }
  end

  defp validation_rate_limited_message do
    "Validation rate limit exceeded. Please try again later."
  end

  defp log_s3_config_audit(
         %Micelio.Accounts.User{} = user,
         %S3Config{} = before_config,
         %S3Config{} = after_config
       ) do
    action =
      if is_nil(before_config.id) do
        "storage.s3_config.created"
      else
        "storage.s3_config.updated"
      end

    case Audit.log_user_action(user, action, metadata: s3_audit_metadata(after_config)) do
      {:ok, _log} ->
        :ok

      {:error, changeset} ->
        Logger.warning("storage.s3_config audit_failed=#{inspect(changeset.errors)}")
    end
  end

  defp log_s3_config_deleted(%Micelio.Accounts.User{} = user, %S3Config{} = config) do
    case Audit.log_user_action(user, "storage.s3_config.deleted",
           metadata: s3_audit_metadata(config)
         ) do
      {:ok, _log} ->
        :ok

      {:error, changeset} ->
        Logger.warning("storage.s3_config audit_failed=#{inspect(changeset.errors)}")
    end
  end

  defp s3_audit_metadata(%S3Config{} = config) do
    %{
      provider: config.provider,
      bucket_name: config.bucket_name,
      region: config.region,
      endpoint_url: config.endpoint_url,
      path_prefix: config.path_prefix
    }
  end
end
