defmodule Micelio.Sessions.Conflict do
  @moduledoc """
  Lightweight bloom filters for session conflict detection.

  Filters are stored as maps with base64-encoded bitsets so they can be persisted
  inside session metadata. They are intentionally small to keep payload sizes low.
  """

  import Bitwise

  @default_size 2048
  @default_hash_count 3

  @doc """
  Builds a bloom filter for the given list of file paths.

  Returns a map with string keys suitable for JSON encoding:

      %{\"size\" => 2048, \"hash_count\" => 3, \"bits\" => \"...\"}
  """
  def build_filter(paths, opts \\ []) when is_list(paths) do
    size = Keyword.get(opts, :size, @default_size)
    hash_count = Keyword.get(opts, :hash_count, @default_hash_count)

    bitset_bytes = div(size + 7, 8)

    bitset =
      Enum.reduce(paths, :binary.copy(<<0>>, bitset_bytes), fn path, acc ->
        Enum.reduce(hash_indexes(path, hash_count, size), acc, fn position, bits ->
          set_bit(bits, position)
        end)
      end)

    %{
      "size" => size,
      "hash_count" => hash_count,
      "bits" => Base.encode64(bitset)
    }
  end

  @doc """
  Checks whether a path might be present in the provided filter.

  Returns true for possible matches (with a small false-positive rate),
  and false when the file is definitely not present.
  """
  def might_conflict?(%{"size" => size, "hash_count" => hash_count, "bits" => encoded_bits}, path) do
    bitset = Base.decode64!(encoded_bits)

    Enum.all?(hash_indexes(path, hash_count, size), fn position ->
      bit_set?(bitset, position)
    end)
  end

  @doc """
  Merges multiple filters by OR-ing their bitsets.
  """
  def merge_filters(filters) when is_list(filters) do
    Enum.reduce(filters, nil, fn filter, acc ->
      merge_filter_pair(acc, filter)
    end)
  end

  defp merge_filter_pair(nil, filter), do: filter
  defp merge_filter_pair(filter, nil), do: filter

  defp merge_filter_pair(%{"size" => size, "hash_count" => hash_count, "bits" => left_bits}, %{
         "size" => size,
         "hash_count" => hash_count,
         "bits" => right_bits
       }) do
    left = Base.decode64!(left_bits)
    right = Base.decode64!(right_bits)

    merged =
      left
      |> :binary.bin_to_list()
      |> Enum.zip(:binary.bin_to_list(right))
      |> Enum.map(fn {l, r} -> :erlang.bor(l, r) end)
      |> :binary.list_to_bin()

    %{
      "size" => size,
      "hash_count" => hash_count,
      "bits" => Base.encode64(merged)
    }
  end

  defp merge_filter_pair(filter, _other), do: filter

  defp hash_indexes(path, hash_count, size) do
    for idx <- 0..(hash_count - 1) do
      :crypto.hash(:sha256, "#{idx}:#{path}")
      |> :binary.part(0, 8)
      |> :binary.decode_unsigned()
      |> rem(size)
    end
  end

  defp set_bit(bitset, position) do
    byte_index = div(position, 8)
    bit_index = rem(position, 8)

    <<prefix::binary-size(byte_index), byte, rest::binary>> = bitset
    updated = :erlang.bor(byte, 1 <<< (7 - bit_index))
    <<prefix::binary, updated, rest::binary>>
  end

  defp bit_set?(bitset, position) do
    byte_index = div(position, 8)
    bit_index = rem(position, 8)

    case bitset do
      <<_::binary-size(byte_index), byte, _::binary>> ->
        :erlang.band(byte, 1 <<< (7 - bit_index)) != 0

      _ ->
        false
    end
  end
end
