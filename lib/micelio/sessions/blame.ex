defmodule Micelio.Sessions.Blame do
  @moduledoc """
  Builds line-level blame attribution from session changes.
  """

  @max_cells 1_000_000

  def build_lines(content, changes) when is_binary(content) and is_list(changes) do
    current_lines = split_lines(content)
    {history_lines, history_attributions} = apply_changes(changes)

    final_attributions =
      cond do
        current_lines == [] ->
          []

        history_lines == [] ->
          Enum.map(current_lines, fn _ -> nil end)

        true ->
          align_attributions(history_lines, history_attributions, current_lines)
      end

    current_lines
    |> Enum.with_index(1)
    |> Enum.zip(final_attributions)
    |> Enum.map(fn {{line, line_number}, attribution} ->
      %{line_number: line_number, text: line, attribution: attribution}
    end)
  end

  defp apply_changes(changes) do
    Enum.reduce(changes, {[], []}, fn change, {lines, attributions} ->
      change_type = Map.get(change, :change_type)
      content = Map.get(change, :content)

      cond do
        change_type == "deleted" ->
          {[], []}

        is_binary(content) ->
          new_lines = split_lines(content)

          new_attributions =
            if lines == [] do
              Enum.map(new_lines, fn _ -> change end)
            else
              line_map = line_map(lines, new_lines)
              old_attributions = List.to_tuple(attributions)

              Enum.map(0..(length(new_lines) - 1), fn idx ->
                case Map.get(line_map, idx) do
                  nil -> change
                  old_idx -> elem(old_attributions, old_idx)
                end
              end)
            end

          {new_lines, new_attributions}

        true ->
          {lines, attributions}
      end
    end)
  end

  defp align_attributions(history_lines, history_attributions, current_lines) do
    line_map = line_map(history_lines, current_lines)
    old_attributions = List.to_tuple(history_attributions)

    Enum.map(0..(length(current_lines) - 1), fn idx ->
      case Map.get(line_map, idx) do
        nil -> nil
        old_idx -> elem(old_attributions, old_idx)
      end
    end)
  end

  defp split_lines(content) do
    String.split(content, "\n", trim: false)
  end

  defp line_map([], _new_lines), do: %{}
  defp line_map(_old_lines, []), do: %{}

  defp line_map(old_lines, new_lines) do
    old_count = length(old_lines)
    new_count = length(new_lines)

    if old_count * new_count > @max_cells do
      fallback_line_map(old_lines, new_lines)
    else
      lcs_line_map(old_lines, new_lines)
    end
  end

  defp fallback_line_map(old_lines, new_lines) do
    old_tuple = List.to_tuple(old_lines)
    new_tuple = List.to_tuple(new_lines)
    limit = min(tuple_size(old_tuple), tuple_size(new_tuple)) - 1

    if limit < 0 do
      %{}
    else
      Enum.reduce(0..limit, %{}, fn idx, acc ->
        if elem(old_tuple, idx) == elem(new_tuple, idx) do
          Map.put(acc, idx, idx)
        else
          acc
        end
      end)
    end
  end

  defp lcs_line_map(old_lines, new_lines) do
    {table, old_tuple, new_tuple} = build_table(old_lines, new_lines)
    pairs = backtrack(table, old_tuple, new_tuple)

    Enum.reduce(pairs, %{}, fn {old_idx, new_idx}, acc ->
      Map.put(acc, new_idx, old_idx)
    end)
  end

  defp build_table(old_lines, new_lines) do
    old_tuple = List.to_tuple(old_lines)
    new_tuple = List.to_tuple(new_lines)
    old_count = tuple_size(old_tuple)
    new_count = tuple_size(new_tuple)
    base_row = :array.new(new_count + 1, default: 0)
    table = :array.new(old_count + 1, default: base_row)

    table =
      Enum.reduce(1..old_count, table, fn i, acc ->
        prev_row = :array.get(i - 1, acc)
        row = :array.new(new_count + 1, default: 0)

        row =
          Enum.reduce(1..new_count, row, fn j, row_acc ->
            if elem(old_tuple, i - 1) == elem(new_tuple, j - 1) do
              :array.set(j, :array.get(j - 1, prev_row) + 1, row_acc)
            else
              left = :array.get(j - 1, row_acc)
              up = :array.get(j, prev_row)
              :array.set(j, max(left, up), row_acc)
            end
          end)

        :array.set(i, row, acc)
      end)

    {table, old_tuple, new_tuple}
  end

  defp backtrack(table, old_tuple, new_tuple) do
    backtrack(table, old_tuple, new_tuple, tuple_size(old_tuple), tuple_size(new_tuple), [])
  end

  defp backtrack(_table, _old_tuple, _new_tuple, 0, _j, acc), do: acc
  defp backtrack(_table, _old_tuple, _new_tuple, _i, 0, acc), do: acc

  defp backtrack(table, old_tuple, new_tuple, i, j, acc) do
    if elem(old_tuple, i - 1) == elem(new_tuple, j - 1) do
      backtrack(table, old_tuple, new_tuple, i - 1, j - 1, [{i - 1, j - 1} | acc])
    else
      up = :array.get(j, :array.get(i - 1, table))
      left = :array.get(j - 1, :array.get(i, table))

      if up >= left do
        backtrack(table, old_tuple, new_tuple, i - 1, j, acc)
      else
        backtrack(table, old_tuple, new_tuple, i, j - 1, acc)
      end
    end
  end
end
