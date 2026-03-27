defmodule Micelio.Changelog do
  @moduledoc """
  The Changelog context for managing changelog entries using NimblePublisher.
  """
  use NimblePublisher,
    # Ensure syntax highlighting aliases are registered before NimblePublisher compiles
    build: Micelio.Changelog.Entry,
    from: Application.app_dir(:micelio, "priv/changelog/**/*.md"),
    as: :entries,
    highlighters: [:makeup_elixir, :makeup_erlang, :makeup_syntect]

  require Micelio.SyntaxHighlighting

  # The @entries variable is first populated at compilation time.
  @entries Enum.sort_by(@entries, & &1.date, {:desc, Date})

  # Let's also get all categories (like features, bugfixes, etc.)
  @categories @entries |> Enum.flat_map(& &1.categories) |> Enum.uniq() |> Enum.sort()

  # And finally export them
  def all_entries, do: @entries
  def all_categories, do: @categories

  def recent_entries(count \\ 10) do
    Enum.take(all_entries(), count)
  end

  def get_entry_by_id!(id) do
    Enum.find(all_entries(), &(&1.id == id)) ||
      raise "changelog entry with id=#{id} not found"
  end

  def get_entries_by_category!(category) do
    case Enum.filter(all_entries(), &(category in &1.categories)) do
      [] -> raise "changelog entries with category=#{category} not found"
      entries -> entries
    end
  end

  def get_entries_by_version!(version) do
    case Enum.filter(all_entries(), &(&1.version == version)) do
      [] -> raise "changelog entries with version=#{version} not found"
      entries -> entries
    end
  end

  def all_versions do
    @entries
    |> Enum.map(& &1.version)
    |> Enum.uniq()
    |> Enum.sort({:desc, Version})
  rescue
    _ ->
      # Fallback if version comparison fails
      @entries
      |> Enum.map(& &1.version)
      |> Enum.uniq()
      |> Enum.sort()
      |> Enum.reverse()
  end
end
