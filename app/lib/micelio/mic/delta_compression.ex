defmodule Micelio.Mic.DeltaCompression do
  @moduledoc """
  Delta compression for blob storage to reduce space for similar files.
  """

  @magic "MICDELTA"
  @version 1
  @hash_size 32
  @header_size byte_size(@magic) + 1 + @hash_size + 4 + 4 + 4

  @spec maybe_encode(binary(), binary(), binary()) :: {:ok, binary()} | :no_delta
  def maybe_encode(base_hash, base_content, content)
      when is_binary(base_hash) and is_binary(base_content) and is_binary(content) do
    if byte_size(base_hash) == @hash_size do
      base_len = byte_size(base_content)
      content_len = byte_size(content)
      limit = min(base_len, content_len)

      prefix_len = common_prefix_len(base_content, content, limit)
      max_suffix = max(limit - prefix_len, 0)
      suffix_len = common_suffix_len(base_content, content, max_suffix)
      middle_len = content_len - prefix_len - suffix_len
      middle = binary_part(content, prefix_len, middle_len)

      payload =
        <<@magic::binary, @version, base_hash::binary-size(@hash_size),
          prefix_len::unsigned-big-32, suffix_len::unsigned-big-32, middle_len::unsigned-big-32,
          middle::binary>>

      if byte_size(payload) + 1 <= content_len do
        {:ok, payload}
      else
        :no_delta
      end
    else
      :no_delta
    end
  end

  @spec decode(binary(), (binary() -> {:ok, binary()} | {:error, term()}), keyword()) ::
          {:ok, binary()} | {:error, term()}
  def decode(content, fetch_base_fun, opts \\ [])
      when is_binary(content) and is_function(fetch_base_fun, 1) do
    max_depth = Keyword.get(opts, :max_depth, 8)
    decode_with_depth(content, fetch_base_fun, max_depth)
  end

  defp decode_with_depth(content, _fetch_base_fun, _depth)
       when byte_size(content) < @header_size do
    {:ok, content}
  end

  defp decode_with_depth(
         <<@magic::binary, @version, base_hash::binary-size(@hash_size),
           prefix_len::unsigned-big-32, suffix_len::unsigned-big-32, middle_len::unsigned-big-32,
           middle::binary-size(middle_len), rest::binary>>,
         fetch_base_fun,
         depth
       ) do
    cond do
      depth <= 0 ->
        {:error, :delta_depth_exceeded}

      rest != <<>> ->
        {:error, :invalid_delta_payload}

      true ->
        with {:ok, base_payload} <- fetch_base_fun.(base_hash),
             {:ok, base_content} <- decode_with_depth(base_payload, fetch_base_fun, depth - 1) do
          reconstruct(base_content, prefix_len, suffix_len, middle)
        end
    end
  end

  defp decode_with_depth(content, _fetch_base_fun, _depth), do: {:ok, content}

  defp reconstruct(base_content, prefix_len, suffix_len, middle)
       when is_binary(base_content) and is_binary(middle) do
    base_len = byte_size(base_content)

    if prefix_len + suffix_len > base_len do
      {:error, :invalid_delta_payload}
    else
      prefix = binary_part(base_content, 0, prefix_len)
      suffix = binary_part(base_content, base_len - suffix_len, suffix_len)
      {:ok, prefix <> middle <> suffix}
    end
  end

  defp common_prefix_len(_base, _content, 0), do: 0

  defp common_prefix_len(base, content, limit) do
    common_prefix_len(base, content, 0, limit)
  end

  defp common_prefix_len(_base, _content, offset, limit) when offset == limit, do: offset

  defp common_prefix_len(base, content, offset, limit) do
    if :binary.at(base, offset) == :binary.at(content, offset) do
      common_prefix_len(base, content, offset + 1, limit)
    else
      offset
    end
  end

  defp common_suffix_len(_base, _content, 0), do: 0

  defp common_suffix_len(base, content, max_suffix) do
    common_suffix_len(base, content, 1, max_suffix)
  end

  defp common_suffix_len(_base, _content, offset, max_suffix) when offset > max_suffix do
    max_suffix
  end

  defp common_suffix_len(base, content, offset, max_suffix) do
    base_index = byte_size(base) - offset
    content_index = byte_size(content) - offset

    if :binary.at(base, base_index) == :binary.at(content, content_index) do
      common_suffix_len(base, content, offset + 1, max_suffix)
    else
      offset - 1
    end
  end
end
