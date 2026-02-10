defmodule Micelio.Mic.Binary do
  @moduledoc """
  Binary serialization helpers for mic storage artifacts.
  """

  @head_magic "MICH"
  @landing_magic "MICL"
  @session_magic "MICS"
  @path_magic "MICP"
  @checkpoint_magic "MICC"
  @version 1
  @zero_hash <<0::size(256)>>

  def zero_hash, do: @zero_hash

  def new_head(position, tree_hash \\ @zero_hash) do
    %{
      position: position,
      tree_hash: tree_hash,
      hlc: default_hlc()
    }
  end

  def encode_head(%{position: position, tree_hash: tree_hash, hlc: hlc}) do
    %{physical: physical, logical: logical, node_id: node_id} = normalize_hlc(hlc)

    <<@head_magic::binary, @version, 0, 0::16, position::unsigned-big-64,
      physical::unsigned-big-64, logical::unsigned-big-32, node_id::unsigned-big-32,
      tree_hash::binary-size(32)>>
  end

  def decode_head(
        <<@head_magic::binary, @version, _flags, _reserved::16, position::unsigned-big-64,
          physical::unsigned-big-64, logical::unsigned-big-32, node_id::unsigned-big-32,
          tree_hash::binary-size(32)>>
      ) do
    {:ok,
     %{
       position: position,
       tree_hash: tree_hash,
       hlc: %{physical: physical, logical: logical, node_id: node_id}
     }}
  end

  def decode_head(_), do: {:error, :invalid_head}

  def encode_landing(%{
        position: position,
        landed_at_ms: landed_at_ms,
        tree_hash: tree_hash,
        session_id: session_id,
        change_filter: change_filter
      }) do
    {filter_flag, filter_payload} = encode_filter(change_filter)
    session_id = to_string(session_id)
    session_len = byte_size(session_id)

    <<@landing_magic::binary, @version, 0, 0::16, position::unsigned-big-64,
      landed_at_ms::unsigned-big-64, tree_hash::binary-size(32), session_len::unsigned-big-16,
      session_id::binary, filter_flag::unsigned-big-8, filter_payload::binary>>
  end

  def decode_landing(
        <<@landing_magic::binary, @version, _flags, _reserved::16, position::unsigned-big-64,
          landed_at_ms::unsigned-big-64, tree_hash::binary-size(32), session_len::unsigned-big-16,
          session_id::binary-size(session_len), filter_flag::unsigned-big-8, rest::binary>>
      ) do
    case decode_filter(filter_flag, rest) do
      {:ok, {change_filter, rest}} ->
        if rest == <<>> do
          {:ok,
           %{
             position: position,
             landed_at_ms: landed_at_ms,
             tree_hash: tree_hash,
             session_id: session_id,
             change_filter: change_filter
           }}
        else
          {:error, :invalid_landing}
        end

      {:error, _} ->
        {:error, :invalid_landing}
    end
  end

  def decode_landing(_), do: {:error, :invalid_landing}

  def encode_session_summary(%{
        session_id: session_id,
        repository_id: repository_id,
        user_id: user_id,
        goal: goal,
        status: status,
        started_at_ms: started_at_ms,
        landed_at_ms: landed_at_ms,
        conversation_count: conversation_count,
        decisions_count: decisions_count
      }) do
    session_id = to_string(session_id)
    repository_id = to_string(repository_id)
    user_id = to_string(user_id)
    goal = to_string(goal)
    status_code = encode_status(status)

    <<@session_magic::binary, @version, status_code::unsigned-big-8, 0::16,
      byte_size(session_id)::unsigned-big-16, session_id::binary,
      byte_size(repository_id)::unsigned-big-16, repository_id::binary,
      byte_size(user_id)::unsigned-big-16, user_id::binary, started_at_ms::unsigned-big-64,
      landed_at_ms::unsigned-big-64, byte_size(goal)::unsigned-big-16, goal::binary,
      conversation_count::unsigned-big-32, decisions_count::unsigned-big-32>>
  end

  def decode_session_summary(
        <<@session_magic::binary, @version, status_code::unsigned-big-8, _reserved::16,
          session_len::unsigned-big-16, session_id::binary-size(session_len),
          project_len::unsigned-big-16, repository_id::binary-size(project_len),
          user_len::unsigned-big-16, user_id::binary-size(user_len),
          started_at_ms::unsigned-big-64, landed_at_ms::unsigned-big-64,
          goal_len::unsigned-big-16, goal::binary-size(goal_len),
          conversation_count::unsigned-big-32, decisions_count::unsigned-big-32>>
      ) do
    {:ok,
     %{
       session_id: session_id,
       repository_id: repository_id,
       user_id: user_id,
       goal: goal,
       status: decode_status(status_code),
       started_at_ms: started_at_ms,
       landed_at_ms: landed_at_ms,
       conversation_count: conversation_count,
       decisions_count: decisions_count
     }}
  end

  def decode_session_summary(_), do: {:error, :invalid_session}

  def encode_filter_index(filter) do
    {flag, payload} = encode_filter(filter)
    <<@landing_magic::binary, @version, flag::unsigned-big-8, 0::16, payload::binary>>
  end

  def decode_filter_index(
        <<@landing_magic::binary, @version, flag::unsigned-big-8, _reserved::16, rest::binary>>
      ) do
    case decode_filter(flag, rest) do
      {:ok, {filter, remaining}} ->
        if remaining == <<>> do
          {:ok, filter}
        else
          {:error, :invalid_filter}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  def decode_filter_index(_), do: {:error, :invalid_filter}

  def encode_path_index(paths) when is_list(paths) do
    entries =
      Enum.map(paths, fn path ->
        path = to_string(path)
        size = byte_size(path)

        if size > 65_535 do
          raise ArgumentError, "path too long for index"
        end

        <<size::unsigned-big-16, path::binary>>
      end)

    count = length(entries)
    payload = IO.iodata_to_binary(entries)

    <<@path_magic::binary, @version, 0, 0::16, count::unsigned-big-32, payload::binary>>
  end

  def decode_path_index(
        <<@path_magic::binary, @version, _flags, _reserved::16, count::unsigned-big-32,
          rest::binary>>
      ) do
    {:ok, decode_path_entries(rest, count, [])}
  rescue
    ArgumentError -> {:error, :invalid_path_index}
  end

  def decode_path_index(_), do: {:error, :invalid_path_index}

  def encode_rollup_checkpoint(position) when is_integer(position) do
    <<@checkpoint_magic::binary, @version, 0, 0::16, position::unsigned-big-64>>
  end

  def decode_rollup_checkpoint(
        <<@checkpoint_magic::binary, @version, _flags, _reserved::16, position::unsigned-big-64>>
      ) do
    {:ok, position}
  end

  def decode_rollup_checkpoint(_), do: {:error, :invalid_checkpoint}

  defp default_hlc do
    %{physical: System.system_time(:millisecond), logical: 0, node_id: 0}
  end

  defp normalize_hlc(%{physical: physical, logical: logical, node_id: node_id}) do
    %{physical: physical, logical: logical, node_id: node_id}
  end

  defp normalize_hlc(_), do: default_hlc()

  defp encode_filter(nil), do: {0, <<>>}

  defp encode_filter(%{"size" => size, "hash_count" => hash_count, "bits" => bits}) do
    bitset = Base.decode64!(bits)

    {1,
     <<size::unsigned-big-32, hash_count::unsigned-big-16, byte_size(bitset)::unsigned-big-32,
       bitset::binary>>}
  end

  defp encode_filter(_), do: {0, <<>>}

  defp decode_filter(0, rest), do: {:ok, {nil, rest}}

  defp decode_filter(
         1,
         <<size::unsigned-big-32, hash_count::unsigned-big-16, bits_len::unsigned-big-32,
           bits::binary-size(bits_len), rest::binary>>
       ) do
    filter = %{
      "size" => size,
      "hash_count" => hash_count,
      "bits" => Base.encode64(bits)
    }

    {:ok, {filter, rest}}
  end

  defp decode_filter(_flag, _rest), do: {:error, :invalid_filter}

  defp encode_status("active"), do: 1
  defp encode_status("landed"), do: 2
  defp encode_status("abandoned"), do: 3
  defp encode_status(_), do: 0

  defp decode_status(1), do: "active"
  defp decode_status(2), do: "landed"
  defp decode_status(3), do: "abandoned"
  defp decode_status(_), do: "unknown"

  defp decode_path_entries(rest, 0, acc) do
    if rest == <<>> do
      Enum.reverse(acc)
    else
      raise ArgumentError, "invalid path index payload"
    end
  end

  defp decode_path_entries(
         <<size::unsigned-big-16, path::binary-size(size), tail::binary>>,
         count,
         acc
       ) do
    decode_path_entries(tail, count - 1, [path | acc])
  end

  defp decode_path_entries(_rest, _count, _acc) do
    raise ArgumentError, "invalid path index payload"
  end
end
