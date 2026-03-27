defmodule Micelio.AgentInfra.SessionManager do
  @moduledoc """
  Defines the API contract and normalization helpers for session managers.
  """

  alias Micelio.AgentInfra.Protocol
  alias Micelio.AgentInfra.SessionRequest

  @typedoc "Unique identifier for a managed session."
  @type session_id :: String.t()

  @typedoc "Canonical session state."
  @type session_state ::
          :queued | :starting | :running | :stopping | :stopped | :failed | :expired

  @typedoc "Supported access channel for a session."
  @type access_type :: :ssh | :http | :grpc | :websocket

  @typedoc "Access endpoint for a session."
  @type access_point :: %{
          type: access_type(),
          uri: String.t(),
          metadata: map()
        }

  @typedoc "Normalized session payload."
  @type session :: %{
          id: session_id(),
          state: session_state(),
          request: SessionRequest.t(),
          instance: Protocol.instance() | nil,
          access: [access_point()],
          created_at: DateTime.t(),
          started_at: DateTime.t() | nil,
          expires_at: DateTime.t() | nil,
          metadata: map()
        }

  @callback create(SessionRequest.t()) :: {:ok, session()} | {:error, term()}
  @callback get(session_id()) :: {:ok, session()} | {:error, term()}
  @callback list(map() | keyword()) :: {:ok, [session()]} | {:error, term()}
  @callback terminate(session_id(), keyword()) :: :ok | {:error, term()}
  @callback extend(session_id(), pos_integer()) :: {:ok, session()} | {:error, term()}
  @callback heartbeat(session_id()) :: :ok | {:error, term()}

  @optional_callbacks extend: 2, heartbeat: 1, list: 1

  @doc "Returns the allowed session states."
  @spec states() :: [session_state()]
  def states do
    [:queued, :starting, :running, :stopping, :stopped, :failed, :expired]
  end

  @doc "Returns the supported access channel types."
  @spec access_types() :: [access_type()]
  def access_types do
    [:ssh, :http, :grpc, :websocket]
  end

  @doc """
  Normalizes a session payload into the canonical session shape.
  """
  @spec normalize_session(term()) :: {:ok, session()} | {:error, term()}
  def normalize_session(%{} = session) do
    with {:ok, id} <- normalize_id(get_field(session, :id)),
         {:ok, state} <- normalize_state(get_field(session, :state)),
         {:ok, request} <- normalize_request(get_field(session, :request)),
         {:ok, instance} <- normalize_instance(get_field(session, :instance)),
         {:ok, access} <- normalize_access(get_field(session, :access)),
         {:ok, created_at} <- normalize_datetime(get_field(session, :created_at), :created_at),
         {:ok, started_at} <- normalize_optional_datetime(get_field(session, :started_at)),
         {:ok, expires_at} <- normalize_optional_datetime(get_field(session, :expires_at)) do
      metadata = normalize_metadata(get_field(session, :metadata))

      {:ok,
       %{
         id: id,
         state: state,
         request: request,
         instance: instance,
         access: access,
         created_at: created_at,
         started_at: started_at,
         expires_at: expires_at,
         metadata: metadata
       }}
    else
      {:error, _reason} = error -> error
    end
  end

  def normalize_session(_session), do: {:error, :invalid_session}

  defp normalize_id(id) when is_binary(id) do
    if String.trim(id) == "" do
      {:error, :invalid_session_id}
    else
      {:ok, id}
    end
  end

  defp normalize_id(_id), do: {:error, :invalid_session_id}

  @states [:queued, :starting, :running, :stopping, :stopped, :failed, :expired]
  defp normalize_state(state) when is_atom(state) and state in @states, do: {:ok, state}

  defp normalize_state(state) when is_binary(state) do
    state = state |> String.trim() |> String.downcase()

    case Enum.find(states(), fn candidate -> Atom.to_string(candidate) == state end) do
      nil -> {:error, :invalid_state}
      value -> {:ok, value}
    end
  end

  defp normalize_state(_state), do: {:error, :invalid_state}

  defp normalize_request(%SessionRequest{} = request), do: {:ok, request}

  defp normalize_request(%{} = attrs) do
    %SessionRequest{}
    |> SessionRequest.changeset(attrs)
    |> Ecto.Changeset.apply_action(:insert)
  end

  defp normalize_request(_request), do: {:error, :invalid_request}

  defp normalize_instance(nil), do: {:ok, nil}

  defp normalize_instance(%{} = instance) do
    case Protocol.normalize_instance(instance) do
      {:ok, normalized} -> {:ok, normalized}
      {:error, _reason} -> {:error, :invalid_instance}
    end
  end

  defp normalize_instance(_instance), do: {:error, :invalid_instance}

  defp normalize_access(nil), do: {:ok, []}

  defp normalize_access(access) when is_list(access) do
    access
    |> Enum.with_index()
    |> Enum.reduce_while({:ok, []}, fn {point, index}, {:ok, acc} ->
      case normalize_access_point(point) do
        {:ok, normalized} -> {:cont, {:ok, [normalized | acc]}}
        {:error, reason} -> {:halt, {:error, %{index: index, reason: reason}}}
      end
    end)
    |> case do
      {:ok, acc} -> {:ok, Enum.reverse(acc)}
      error -> error
    end
  end

  defp normalize_access(_access), do: {:error, :invalid_access}

  defp normalize_access_point(%{} = point) do
    with {:ok, type} <- normalize_access_type(get_field(point, :type)),
         {:ok, uri} <- normalize_uri(get_field(point, :uri)) do
      metadata = normalize_metadata(get_field(point, :metadata))
      {:ok, %{type: type, uri: uri, metadata: metadata}}
    else
      {:error, _reason} = error -> error
    end
  end

  defp normalize_access_point(_point), do: {:error, :invalid_access_point}

  @access_types [:ssh, :http, :grpc, :websocket]
  defp normalize_access_type(type) when is_atom(type) and type in @access_types, do: {:ok, type}

  defp normalize_access_type(type) when is_binary(type) do
    type = type |> String.trim() |> String.downcase()

    case Enum.find(access_types(), fn candidate -> Atom.to_string(candidate) == type end) do
      nil -> {:error, :invalid_access_type}
      value -> {:ok, value}
    end
  end

  defp normalize_access_type(_type), do: {:error, :invalid_access_type}

  defp normalize_uri(uri) when is_binary(uri) do
    if String.trim(uri) == "" do
      {:error, :invalid_access_uri}
    else
      {:ok, uri}
    end
  end

  defp normalize_uri(_uri), do: {:error, :invalid_access_uri}

  defp normalize_datetime(%DateTime{} = value, _field), do: {:ok, value}
  defp normalize_datetime(_value, field), do: {:error, {:invalid_timestamp, field}}

  defp normalize_optional_datetime(nil), do: {:ok, nil}
  defp normalize_optional_datetime(%DateTime{} = value), do: {:ok, value}
  defp normalize_optional_datetime(_value), do: {:error, :invalid_timestamp}

  defp normalize_metadata(%{} = metadata), do: metadata
  defp normalize_metadata(_metadata), do: %{}

  defp get_field(map, key) do
    Map.get(map, key) || Map.get(map, Atom.to_string(key))
  end
end
