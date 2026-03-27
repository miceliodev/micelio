defmodule Micelio.AgentInfra.Protocol do
  @moduledoc """
  Defines the shared protocol shapes for cloud-agnostic VM providers.

  Provider implementations can normalize external responses into this
  protocol to keep the rest of the system consistent across platforms.
  """

  @typedoc "Canonical VM lifecycle state."
  @type state :: :starting | :running | :stopped | :terminated | :error

  @typedoc "Normalized status payload for a VM instance."
  @type status :: %{
          state: state(),
          hostname: String.t() | nil,
          ip_address: String.t() | nil,
          metadata: map()
        }

  @typedoc "Normalized instance payload returned by providers."
  @type instance :: %{
          ref: term(),
          status: status(),
          provider: String.t() | nil,
          metadata: map()
        }

  @typedoc "Normalized instance list payload returned by providers."
  @type instances :: [instance()]

  @typedoc "Normalized range for numeric capabilities."
  @type range :: %{
          min: pos_integer() | nil,
          max: pos_integer() | nil
        }

  @typedoc "Normalized capabilities payload for a provider."
  @type capabilities :: %{
          cpu_cores: range(),
          memory_mb: range(),
          disk_gb: range(),
          networks: [String.t()],
          volume_types: [String.t()],
          metadata: map()
        }

  @typedoc "Normalized provider error payload."
  @type error :: %{
          code: String.t(),
          message: String.t() | nil,
          retryable: boolean(),
          metadata: map()
        }

  @doc "Returns the allowed VM lifecycle states."
  @spec states() :: [state()]
  def states do
    [:starting, :running, :stopped, :terminated, :error]
  end

  @doc """
  Normalizes a provider status payload into the canonical protocol shape.
  """
  @spec normalize_status(term()) :: {:ok, status()} | {:error, atom()}
  def normalize_status(%{} = status) do
    case normalize_state(get_field(status, :state)) do
      {:ok, state} ->
        hostname = normalize_hostname(get_field(status, :hostname))
        ip_address = normalize_ip_address(get_field(status, :ip_address))
        metadata = normalize_metadata(get_field(status, :metadata))

        {:ok,
         %{
           state: state,
           hostname: hostname,
           ip_address: ip_address,
           metadata: metadata
         }}

      {:error, _reason} = error ->
        error
    end
  end

  def normalize_status(_status), do: {:error, :invalid_status}

  @doc """
  Normalizes a provider instance payload into the canonical protocol shape.
  """
  @spec normalize_instance(term()) :: {:ok, instance()} | {:error, atom()}
  def normalize_instance(%{} = instance) do
    with {:ok, ref} <- normalize_ref(get_field(instance, :ref)),
         {:ok, status} <- normalize_status(get_field(instance, :status)) do
      provider = normalize_provider(get_field(instance, :provider))
      metadata = normalize_metadata(get_field(instance, :metadata))

      {:ok,
       %{
         ref: ref,
         status: status,
         provider: provider,
         metadata: metadata
       }}
    else
      {:error, _reason} = error -> error
    end
  end

  def normalize_instance(_instance), do: {:error, :invalid_instance}

  @doc """
  Normalizes a list of provider instance payloads into the canonical protocol shape.
  """
  @spec normalize_instances(list() | nil) ::
          {:ok, instances()}
          | {:error, :invalid_instances | %{index: non_neg_integer(), reason: atom()}}
  def normalize_instances(nil), do: {:ok, []}

  def normalize_instances(instances) when is_list(instances) do
    instances
    |> Enum.with_index()
    |> Enum.reduce_while({:ok, []}, fn {instance, index}, {:ok, acc} ->
      case normalize_instance(instance) do
        {:ok, normalized} -> {:cont, {:ok, [normalized | acc]}}
        {:error, reason} -> {:halt, {:error, %{index: index, reason: reason}}}
      end
    end)
    |> case do
      {:ok, acc} -> {:ok, Enum.reverse(acc)}
      error -> error
    end
  end

  def normalize_instances(_instances), do: {:error, :invalid_instances}

  @doc """
  Normalizes provider capabilities into the canonical protocol shape.
  """
  @spec normalize_capabilities(map() | nil) :: {:ok, capabilities()} | {:error, atom()}
  def normalize_capabilities(nil), do: {:ok, default_capabilities()}

  def normalize_capabilities(%{} = capabilities) do
    {:ok,
     %{
       cpu_cores: normalize_range(get_field(capabilities, :cpu_cores)),
       memory_mb: normalize_range(get_field(capabilities, :memory_mb)),
       disk_gb: normalize_range(get_field(capabilities, :disk_gb)),
       networks: normalize_list(get_field(capabilities, :networks)),
       volume_types: normalize_list(get_field(capabilities, :volume_types)),
       metadata: normalize_metadata(get_field(capabilities, :metadata))
     }}
  end

  def normalize_capabilities(_capabilities), do: {:error, :invalid_capabilities}

  @doc """
  Normalizes provider error payloads into the canonical protocol shape.
  """
  @spec normalize_error(term()) :: {:ok, error()} | {:error, atom()}
  def normalize_error(%{} = error) do
    case normalize_error_code(get_field(error, :code)) do
      {:ok, code} ->
        message = normalize_error_message(get_field(error, :message))
        retryable = normalize_boolean(get_field(error, :retryable))
        metadata = normalize_metadata(get_field(error, :metadata))

        {:ok,
         %{
           code: code,
           message: message,
           retryable: retryable,
           metadata: metadata
         }}

      {:error, _reason} = error ->
        error
    end
  end

  def normalize_error(_error), do: {:error, :invalid_error}

  defp normalize_state(state) when state in [:starting, :running, :stopped, :terminated, :error],
    do: {:ok, state}

  defp normalize_state(state) when is_binary(state) do
    state
    |> String.downcase()
    |> String.to_existing_atom()
    |> normalize_state()
  rescue
    ArgumentError -> {:error, :invalid_state}
  end

  defp normalize_state(_state), do: {:error, :invalid_state}

  defp normalize_ref(nil), do: {:error, :invalid_instance_ref}
  defp normalize_ref(ref), do: {:ok, ref}

  defp normalize_hostname(nil), do: nil
  defp normalize_hostname(value) when is_binary(value), do: value
  defp normalize_hostname(value) when is_list(value), do: to_string(value)
  defp normalize_hostname(_value), do: nil

  defp normalize_ip_address(nil), do: nil
  defp normalize_ip_address(value) when is_binary(value), do: value

  defp normalize_ip_address(value) when is_tuple(value) do
    value
    |> :inet.ntoa()
    |> to_string()
  rescue
    _ -> nil
  end

  defp normalize_ip_address(value) when is_list(value), do: to_string(value)
  defp normalize_ip_address(_value), do: nil

  defp normalize_provider(nil), do: nil
  defp normalize_provider(provider) when is_binary(provider), do: provider
  defp normalize_provider(provider) when is_atom(provider), do: Atom.to_string(provider)
  defp normalize_provider(_provider), do: nil

  defp normalize_metadata(nil), do: %{}
  defp normalize_metadata(metadata) when is_map(metadata), do: metadata
  defp normalize_metadata(_metadata), do: %{}

  defp default_capabilities do
    %{
      cpu_cores: %{min: nil, max: nil},
      memory_mb: %{min: nil, max: nil},
      disk_gb: %{min: nil, max: nil},
      networks: [],
      volume_types: [],
      metadata: %{}
    }
  end

  defp normalize_range(nil), do: %{min: nil, max: nil}

  defp normalize_range(%{} = range) do
    %{
      min: normalize_positive_int(get_field(range, :min)),
      max: normalize_positive_int(get_field(range, :max))
    }
  end

  defp normalize_range(_range), do: %{min: nil, max: nil}

  defp normalize_list(nil), do: []
  defp normalize_list(value) when is_binary(value), do: [value]

  defp normalize_list(value) when is_list(value) do
    value
    |> Enum.map(&normalize_list_item/1)
    |> Enum.reject(&is_nil/1)
  end

  defp normalize_list(_value), do: []

  defp normalize_list_item(value) when is_binary(value), do: value
  defp normalize_list_item(value) when is_atom(value), do: Atom.to_string(value)
  defp normalize_list_item(_value), do: nil

  defp normalize_positive_int(value) when is_integer(value) and value > 0, do: value

  defp normalize_positive_int(value) when is_binary(value) do
    case Integer.parse(value) do
      {int, ""} when int > 0 -> int
      _ -> nil
    end
  end

  defp normalize_positive_int(_value), do: nil

  defp normalize_error_code(nil), do: {:error, :invalid_error_code}

  defp normalize_error_code(code) when is_atom(code) do
    {:ok, Atom.to_string(code)}
  end

  defp normalize_error_code(code) when is_binary(code) do
    trimmed = String.trim(code)

    if trimmed == "" do
      {:error, :invalid_error_code}
    else
      {:ok, trimmed}
    end
  end

  defp normalize_error_code(_code), do: {:error, :invalid_error_code}

  defp normalize_error_message(nil), do: nil
  defp normalize_error_message(message) when is_binary(message), do: message
  defp normalize_error_message(message) when is_atom(message), do: Atom.to_string(message)
  defp normalize_error_message(_message), do: nil

  defp normalize_boolean(value) when is_boolean(value), do: value

  defp normalize_boolean(value) when is_binary(value) do
    case String.downcase(String.trim(value)) do
      "true" -> true
      "false" -> false
      _ -> false
    end
  end

  defp normalize_boolean(_value), do: false

  defp get_field(map, key) do
    Map.get(map, key) || Map.get(map, Atom.to_string(key))
  end
end
