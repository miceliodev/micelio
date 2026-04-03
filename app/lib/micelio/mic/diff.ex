defmodule Micelio.Mic.Diff do
  @moduledoc """
  Generates unified diff strings from old and new file content
  using the Myers difference algorithm.
  """

  @context_lines 3

  def unified_diff(old_content, new_content, file_path, opts \\ [])

  def unified_diff(nil, nil, _file_path, _opts), do: {:ok, nil}

  def unified_diff(old, new, _file_path, _opts) when old == new, do: {:ok, nil}

  def unified_diff(old_content, new_content, file_path, _opts) do
    old_lines = split_lines(old_content || "")
    new_lines = split_lines(new_content || "")

    diff_ops = List.myers_difference(old_lines, new_lines)
    hunks = build_hunks(diff_ops, @context_lines)

    if hunks == [] do
      {:ok, nil}
    else
      header = "--- a/#{file_path}\n+++ b/#{file_path}\n"
      body = Enum.map_join(hunks, "\n", &format_hunk/1)
      {:ok, header <> body <> "\n"}
    end
  end

  defp split_lines(content) when is_binary(content) do
    String.split(content, ~r/\r?\n/, include_captures: false)
  end

  defp split_lines(_), do: []

  defp build_hunks(diff_ops, context) do
    annotated = annotate_lines(diff_ops)

    annotated
    |> find_change_ranges(context)
    |> Enum.map(fn {start_idx, end_idx} ->
      slice = Enum.slice(annotated, start_idx..end_idx)
      build_hunk(slice, start_idx, annotated)
    end)
  end

  defp annotate_lines(diff_ops) do
    {lines, _old_line, _new_line} =
      Enum.reduce(diff_ops, {[], 1, 1}, fn
        {:eq, equal_lines}, {acc, old_ln, new_ln} ->
          entries =
            equal_lines
            |> Enum.with_index()
            |> Enum.map(fn {line, i} ->
              {:context, line, old_ln + i, new_ln + i}
            end)

          {acc ++ entries, old_ln + length(equal_lines), new_ln + length(equal_lines)}

        {:del, removed_lines}, {acc, old_ln, new_ln} ->
          entries =
            removed_lines
            |> Enum.with_index()
            |> Enum.map(fn {line, i} ->
              {:del, line, old_ln + i, nil}
            end)

          {acc ++ entries, old_ln + length(removed_lines), new_ln}

        {:ins, added_lines}, {acc, old_ln, new_ln} ->
          entries =
            added_lines
            |> Enum.with_index()
            |> Enum.map(fn {line, i} ->
              {:ins, line, nil, new_ln + i}
            end)

          {acc ++ entries, old_ln, new_ln + length(added_lines)}
      end)

    lines
  end

  defp find_change_ranges(annotated, context) do
    change_indices =
      annotated
      |> Enum.with_index()
      |> Enum.filter(fn {{type, _, _, _}, _idx} -> type in [:del, :ins] end)
      |> Enum.map(fn {_, idx} -> idx end)

    if change_indices == [] do
      []
    else
      max_idx = length(annotated) - 1

      change_indices
      |> Enum.reduce([], fn idx, ranges ->
        range_start = max(0, idx - context)
        range_end = min(max_idx, idx + context)

        case ranges do
          [{s, e} | rest] when range_start <= e + 1 ->
            [{s, max(e, range_end)} | rest]

          _ ->
            [{range_start, range_end} | ranges]
        end
      end)
      |> Enum.reverse()
    end
  end

  defp build_hunk(slice, _start_idx, _annotated) do
    old_start = find_first_line_number(slice, :old)
    new_start = find_first_line_number(slice, :new)
    old_count = Enum.count(slice, fn {type, _, _, _} -> type in [:context, :del] end)
    new_count = Enum.count(slice, fn {type, _, _, _} -> type in [:context, :ins] end)

    %{
      old_start: old_start,
      old_count: old_count,
      new_start: new_start,
      new_count: new_count,
      lines: slice
    }
  end

  defp find_first_line_number(slice, :old) do
    case Enum.find(slice, fn {type, _, _, _} -> type in [:context, :del] end) do
      {_, _, old_ln, _} -> old_ln
      nil -> 1
    end
  end

  defp find_first_line_number(slice, :new) do
    case Enum.find(slice, fn {type, _, _, _} -> type in [:context, :ins] end) do
      {_, _, _, new_ln} -> new_ln
      nil -> 1
    end
  end

  defp format_hunk(%{
         old_start: old_start,
         old_count: old_count,
         new_start: new_start,
         new_count: new_count,
         lines: lines
       }) do
    header = "@@ -#{old_start},#{old_count} +#{new_start},#{new_count} @@"

    body =
      Enum.map_join(lines, "\n", fn
        {:context, line, _, _} -> " #{line}"
        {:del, line, _, _} -> "-#{line}"
        {:ins, line, _, _} -> "+#{line}"
      end)

    header <> "\n" <> body
  end
end
