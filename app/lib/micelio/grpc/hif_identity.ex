defmodule Micelio.GRPC.Hif.Identity do
  @moduledoc false

  alias Micelio.Accounts
  alias Micelio.Fediverse
  alias Micelio.GRPC.Hif.V1

  def attributed_to_for_session(nil), do: %V1.IdentityRef{}

  def attributed_to_for_session(%{user: %{account: %{handle: handle}}}) when is_binary(handle) do
    identity_from_handle(handle, "user")
  end

  def attributed_to_for_session(%{user_id: user_id}) when is_binary(user_id) do
    case Accounts.get_user_with_account(user_id) do
      %{account: %{handle: handle}} when is_binary(handle) and handle != "" ->
        identity_from_handle(handle, "user")

      _ ->
        %V1.IdentityRef{kind: "user"}
    end
  end

  def attributed_to_for_session(_session), do: %V1.IdentityRef{kind: "user"}

  def attributed_to_for_handle(handle) when is_binary(handle) do
    identity_from_handle(handle, "user")
  end

  def attributed_to_for_handle(_handle), do: %V1.IdentityRef{kind: "user"}

  def performed_by_for_session(nil), do: %V1.IdentityRef{}

  def performed_by_for_session(session) do
    metadata = normalize_metadata(Map.get(session, :metadata))
    attributed_to = attributed_to_for_session(session)
    contributor_type = Map.get(metadata, "contributor_type", "human")

    if contributor_type in ["ai", "mixed"] do
      agent_identity(session, metadata, attributed_to)
    else
      %{attributed_to | kind: "user"}
    end
  end

  defp identity_from_handle(handle, kind) when is_binary(handle) and is_binary(kind) do
    trimmed = String.trim(handle)

    if trimmed == "" do
      %V1.IdentityRef{kind: kind}
    else
      acct = fediverse_acct(trimmed)

      %V1.IdentityRef{
        id: Fediverse.actor_url(trimmed),
        acct: acct,
        handle: trimmed,
        instance: instance_from_acct(acct),
        kind: kind
      }
    end
  end

  defp agent_identity(session, metadata, attributed_to) do
    session_id =
      case Map.get(session, :session_id) do
        value when is_binary(value) and value != "" -> value
        _ -> "unknown"
      end

    id = blank_to_nil(Map.get(metadata, "agent_actor_id")) || "urn:hif:agent:#{session_id}"

    handle =
      blank_to_nil(Map.get(metadata, "tool_name")) || blank_to_nil(Map.get(metadata, "model_id")) ||
        "agent"

    instance = blank_to_nil(attributed_to.instance) || default_instance()

    %V1.IdentityRef{
      id: id,
      acct: "agent+#{session_id}@#{instance}",
      handle: handle,
      instance: instance,
      kind: "agent"
    }
  end

  defp fediverse_acct(handle) do
    case Fediverse.webfinger_subject(handle) do
      "acct:" <> acct -> acct
      _ -> ""
    end
  end

  defp default_instance do
    case Fediverse.webfinger_subject("agent") do
      "acct:agent@" <> instance -> instance
      _ -> ""
    end
  end

  defp instance_from_acct(acct) when is_binary(acct) do
    case String.split(acct, "@", parts: 2) do
      [_handle, instance] -> instance
      _ -> ""
    end
  end

  defp normalize_metadata(%{} = metadata) do
    Enum.reduce(metadata, %{}, fn {key, value}, acc ->
      Map.put(acc, to_string(key), value)
    end)
  end

  defp normalize_metadata(_), do: %{}

  defp blank_to_nil(value) when is_binary(value) do
    trimmed = String.trim(value)
    if trimmed != "", do: trimmed
  end

  defp blank_to_nil(_), do: nil
end
