defmodule Micelio.Auth.CBOR do
  @moduledoc false

  def decode(binary) when is_binary(binary) do
    case decode_item(binary) do
      {:ok, value, rest} -> {:ok, value, rest}
      {:error, _reason} -> {:error, :invalid_cbor}
    end
  end

  defp decode_item(<<major::3, addl::5, rest::binary>>) do
    with {:ok, length, rest} <- read_length(addl, rest) do
      case major do
        0 -> {:ok, length, rest}
        1 -> {:ok, -1 - length, rest}
        2 -> read_bytes(length, rest)
        3 -> read_text(length, rest)
        4 -> read_array(length, rest)
        5 -> read_map(length, rest)
        _ -> {:error, :unsupported_type}
      end
    end
  end

  defp decode_item(_), do: {:error, :invalid_cbor}

  defp read_length(addl, rest) when addl < 24, do: {:ok, addl, rest}

  defp read_length(24, <<value::unsigned-8, rest::binary>>), do: {:ok, value, rest}
  defp read_length(25, <<value::unsigned-big-16, rest::binary>>), do: {:ok, value, rest}
  defp read_length(26, <<value::unsigned-big-32, rest::binary>>), do: {:ok, value, rest}
  defp read_length(27, <<value::unsigned-big-64, rest::binary>>), do: {:ok, value, rest}
  defp read_length(_, _), do: {:error, :invalid_length}

  defp read_bytes(length, binary) do
    case binary do
      <<value::binary-size(length), rest::binary>> -> {:ok, value, rest}
      _ -> {:error, :invalid_length}
    end
  end

  defp read_text(length, binary) do
    case binary do
      <<value::binary-size(length), rest::binary>> -> {:ok, value, rest}
      _ -> {:error, :invalid_length}
    end
  end

  defp read_array(length, binary), do: read_array(length, binary, [])

  defp read_array(0, rest, acc), do: {:ok, Enum.reverse(acc), rest}

  defp read_array(length, binary, acc) when length > 0 do
    with {:ok, value, rest} <- decode_item(binary) do
      read_array(length - 1, rest, [value | acc])
    end
  end

  defp read_map(length, binary), do: read_map(length, binary, %{})

  defp read_map(0, rest, acc), do: {:ok, acc, rest}

  defp read_map(length, binary, acc) when length > 0 do
    with {:ok, key, rest} <- decode_item(binary),
         {:ok, value, rest} <- decode_item(rest) do
      read_map(length - 1, rest, Map.put(acc, key, value))
    end
  end
end
