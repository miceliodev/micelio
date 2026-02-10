defmodule Micelio.Mic.Tree do
  @moduledoc """
  Tree serialization and hashing for mic storage.
  """

  @magic "MICT"
  @version 1

  def empty, do: %{}

  def encode(tree) when is_map(tree) do
    entries =
      tree
      |> Map.to_list()
      |> Enum.sort_by(fn {path, _hash} -> path end)

    header = <<@magic::binary, @version, 0, 0::16, length(entries)::unsigned-big-32>>

    body =
      Enum.map_join(entries, fn {path, hash} ->
        path = to_string(path)
        path_len = byte_size(path)

        if path_len > 65_535 do
          raise ArgumentError, "path too long for tree entry: #{path_len}"
        end

        <<path_len::unsigned-big-16, path::binary, hash::binary-size(32)>>
      end)

    header <> body
  end

  def decode(
        <<@magic::binary, @version, _flags, _reserved::16, count::unsigned-big-32, rest::binary>>
      ) do
    decode_entries(rest, count, %{})
  end

  def decode(_), do: {:error, :invalid_tree}

  def hash(encoded_tree) when is_binary(encoded_tree) do
    :crypto.hash(:sha256, encoded_tree)
  end

  def put(tree, path, hash) when is_binary(hash) do
    Map.put(tree, path, hash)
  end

  def delete(tree, path) do
    Map.delete(tree, path)
  end

  defp decode_entries(rest, 0, acc) do
    if rest == <<>> do
      {:ok, acc}
    else
      {:error, :invalid_tree}
    end
  end

  defp decode_entries(<<path_len::unsigned-big-16, rest::binary>>, count, acc)
       when byte_size(rest) >= path_len + 32 do
    <<path::binary-size(path_len), hash::binary-size(32), tail::binary>> = rest
    decode_entries(tail, count - 1, Map.put(acc, path, hash))
  end

  defp decode_entries(_rest, _count, _acc), do: {:error, :invalid_tree}
end
