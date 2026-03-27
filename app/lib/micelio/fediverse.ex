defmodule Micelio.Fediverse do
  @moduledoc """
  ActivityPub helpers for exposing Micelio accounts to the fediverse.
  """

  import Ecto.Query

  alias Micelio.Accounts
  alias Micelio.Accounts.Account
  alias Micelio.Fediverse.Follower
  alias Micelio.Repo
  alias Micelio.Repositories
  alias Micelio.Repositories.Repository

  @activity_context "https://www.w3.org/ns/activitystreams"
  @security_context "https://w3id.org/security/v1"

  def webfinger_subject(handle) when is_binary(handle) do
    "acct:#{handle}@#{host_with_port()}"
  end

  def webfinger_response(handle) when is_binary(handle) do
    %{
      "subject" => webfinger_subject(handle),
      "links" => [
        %{
          "rel" => "self",
          "type" => "application/activity+json",
          "href" => actor_url(handle)
        }
      ]
    }
  end

  def parse_webfinger_resource("acct:" <> resource) do
    case String.split(resource, "@", parts: 2) do
      [handle, host] ->
        if host == host_with_port() do
          {:ok, handle}
        else
          {:error, :not_found}
        end

      _ ->
        {:error, :not_found}
    end
  end

  def parse_webfinger_resource(_resource), do: {:error, :not_found}

  def account_for_handle(handle) when is_binary(handle) do
    case Accounts.get_account_by_handle(handle) do
      %Account{} = account -> {:ok, Repo.preload(account, [:user, :organization])}
      _ -> {:error, :not_found}
    end
  end

  def repository_for_handle(account_handle, repository_handle)
      when is_binary(account_handle) and is_binary(repository_handle) do
    with {:ok, organization} <- Accounts.get_organization_by_handle(account_handle),
         %Repository{} = repository <-
           Repositories.get_repository_by_handle(organization.id, repository_handle),
         true <- repository.visibility == "public" do
      {:ok, {organization.account, repository}}
    else
      _ -> {:error, :not_found}
    end
  end

  def actor_payload(%Account{} = account) do
    handle = account.handle
    actor_url = actor_url(handle)
    actor_type = if Account.organization?(account), do: "Organization", else: "Person"

    %{
      "@context" => [@activity_context, @security_context],
      "id" => actor_url,
      "type" => actor_type,
      "preferredUsername" => handle,
      "name" => display_name(account),
      "url" => profile_url(handle),
      "inbox" => inbox_url(handle),
      "outbox" => outbox_url(handle),
      "followers" => followers_url(handle),
      "following" => following_url(handle)
    }
    |> maybe_put_public_key(actor_url)
  end

  def profile_payload(%Account{} = account) do
    handle = account.handle

    %{
      "@context" => @activity_context,
      "id" => profile_activity_url(handle),
      "type" => "Profile",
      "name" => display_name(account),
      "url" => profile_url(handle),
      "describes" => actor_url(handle)
    }
  end

  def repository_payload(%Account{} = account, %Repository{} = repository) do
    account_handle = account.handle
    repository_handle = repository.handle

    %{
      "@context" => @activity_context,
      "id" => repository_activity_url(account_handle, repository_handle),
      "type" => "Project",
      "name" => repository.name || repository.handle,
      "url" => repository_url(account_handle, repository_handle),
      "attributedTo" => actor_url(account_handle)
    }
    |> maybe_put_summary(repository.description)
    |> maybe_put_timestamp("published", repository.inserted_at)
    |> maybe_put_timestamp("updated", repository.updated_at)
  end

  def outbox_payload(handle) when is_binary(handle) do
    %{
      "@context" => @activity_context,
      "id" => outbox_url(handle),
      "type" => "OrderedCollection",
      "totalItems" => 0,
      "orderedItems" => []
    }
  end

  def followers_payload(%Account{} = account) do
    actors = list_follower_actors(account)

    %{
      "@context" => @activity_context,
      "id" => followers_url(account.handle),
      "type" => "OrderedCollection",
      "totalItems" => length(actors),
      "orderedItems" => actors
    }
  end

  def following_payload(%Account{} = account) do
    %{
      "@context" => @activity_context,
      "id" => following_url(account.handle),
      "type" => "OrderedCollection",
      "totalItems" => 0,
      "orderedItems" => []
    }
  end

  def actor_url(handle) when is_binary(handle), do: absolute_url("/ap/actors/#{handle}")
  def inbox_url(handle) when is_binary(handle), do: absolute_url("/ap/actors/#{handle}/inbox")
  def outbox_url(handle) when is_binary(handle), do: absolute_url("/ap/actors/#{handle}/outbox")

  def followers_url(handle) when is_binary(handle),
    do: absolute_url("/ap/actors/#{handle}/followers")

  def following_url(handle) when is_binary(handle),
    do: absolute_url("/ap/actors/#{handle}/following")

  def profile_activity_url(handle) when is_binary(handle),
    do: absolute_url("/ap/profiles/#{handle}")

  def repository_activity_url(account_handle, repository_handle)
      when is_binary(account_handle) and is_binary(repository_handle) do
    absolute_url("/ap/repositories/#{account_handle}/#{repository_handle}")
  end

  def repository_url(account_handle, repository_handle)
      when is_binary(account_handle) and is_binary(repository_handle) do
    absolute_url("/#{account_handle}/#{repository_handle}")
  end

  def profile_url(handle) when is_binary(handle), do: absolute_url("/#{handle}")

  def list_follower_actors(%Account{} = account) do
    account.id
    |> followers_query()
    |> select([f], f.actor)
    |> order_by([f], asc: f.inserted_at)
    |> Repo.all()
  end

  def upsert_follower(%Account{} = account, actor, inbox \\ nil) when is_binary(actor) do
    attrs = %{account_id: account.id, actor: actor, inbox: inbox}

    %Follower{}
    |> Follower.changeset(attrs)
    |> Repo.insert(on_conflict: :nothing, conflict_target: [:account_id, :actor])
  end

  def remove_follower(%Account{} = account, actor) when is_binary(actor) do
    account.id
    |> followers_query()
    |> where([f], f.actor == ^actor)
    |> Repo.delete_all()

    {:ok, :removed}
  end

  def process_inbox_activity(%Account{} = account, %{"type" => "Follow"} = activity) do
    with {:ok, {actor, inbox}} <- extract_actor_info(activity) do
      upsert_follower(account, actor, inbox)
    end
  end

  def process_inbox_activity(%Account{} = account, %{"type" => "Undo"} = activity) do
    with {:ok, actor} <- extract_actor_id(activity),
         :ok <- ensure_undo_follow(activity) do
      remove_follower(account, actor)
    end
  end

  def process_inbox_activity(_account, _activity), do: {:error, :bad_request}

  defp display_name(%Account{organization: %{name: name}}) when is_binary(name) and name != "",
    do: name

  defp display_name(%Account{handle: handle}), do: handle

  defp followers_query(account_id) do
    from(f in Follower, where: f.account_id == ^account_id)
  end

  defp extract_actor_info(%{"actor" => actor}) do
    case actor do
      %{"id" => actor_id} when is_binary(actor_id) ->
        inbox =
          case Map.get(actor, "inbox") do
            inbox_value when is_binary(inbox_value) -> inbox_value
            _ -> nil
          end

        {:ok, {actor_id, inbox}}

      actor_id when is_binary(actor_id) ->
        {:ok, {actor_id, nil}}

      _ ->
        {:error, :bad_request}
    end
  end

  defp extract_actor_info(_activity), do: {:error, :bad_request}

  defp extract_actor_id(activity) do
    case extract_actor_info(activity) do
      {:ok, {actor_id, _inbox}} -> {:ok, actor_id}
      {:error, reason} -> {:error, reason}
    end
  end

  defp ensure_undo_follow(%{"object" => %{"type" => "Follow"}}), do: :ok
  defp ensure_undo_follow(%{"object" => object}) when is_binary(object), do: :ok
  defp ensure_undo_follow(_activity), do: {:error, :bad_request}

  defp maybe_put_public_key(payload, actor_url) do
    case Application.get_env(:micelio, :activity_pub_public_key) do
      key when is_binary(key) and key != "" ->
        Map.put(payload, "publicKey", %{
          "id" => actor_url <> "#main-key",
          "owner" => actor_url,
          "publicKeyPem" => key
        })

      _ ->
        payload
    end
  end

  defp maybe_put_summary(payload, summary) when is_binary(summary) do
    if summary == "" do
      payload
    else
      Map.put(payload, "summary", summary)
    end
  end

  defp maybe_put_summary(payload, _summary), do: payload

  defp maybe_put_timestamp(payload, key, timestamp) do
    case format_datetime(timestamp) do
      nil -> payload
      formatted -> Map.put(payload, key, formatted)
    end
  end

  defp format_datetime(%DateTime{} = timestamp), do: DateTime.to_iso8601(timestamp)

  defp format_datetime(%NaiveDateTime{} = timestamp) do
    timestamp
    |> DateTime.from_naive!("Etc/UTC")
    |> DateTime.to_iso8601()
  end

  defp format_datetime(_timestamp), do: nil

  defp absolute_url(path) do
    MicelioWeb.Endpoint.url() <> path
  end

  defp host_with_port do
    uri = URI.parse(MicelioWeb.Endpoint.url())
    host = uri.host || "localhost"

    cond do
      is_nil(uri.port) ->
        host

      uri.scheme == "http" and uri.port == 80 ->
        host

      uri.scheme == "https" and uri.port == 443 ->
        host

      true ->
        "#{host}:#{uri.port}"
    end
  end
end
