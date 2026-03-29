defmodule Micelio.Docs do
  @moduledoc """
  The Docs context for managing documentation pages using NimblePublisher.

  Docs are organized by category in the filesystem:
  - priv/docs/auth/authentication.md

  Page ordering is defined in `_index.txt` files within each category directory.
  Each line in the index file is a page ID (filename without extension).
  """
  use Gettext, backend: MicelioWeb.Gettext

  use NimblePublisher,
    # Ensure syntax highlighting aliases are registered before NimblePublisher compiles
    build: Micelio.Docs.Page,
    from: Application.app_dir(:micelio, "priv/docs/**/*.md"),
    as: :pages,
    html_converter: Micelio.Docs.HtmlConverter,
    highlighters: [:makeup_elixir, :makeup_erlang, :makeup_syntect]

  require Micelio.SyntaxHighlighting

  @categories %{
    "grpc" => %{
      title: gettext_noop("gRPC API"),
      description: gettext_noop("gRPC API reference generated from protocol buffer definitions."),
      kind: :reference
    },
    "rest-api" => %{
      title: gettext_noop("REST API"),
      description: gettext_noop("REST API reference with endpoints, error format, and examples."),
      kind: :reference
    },
    "auth" => %{
      title: gettext_noop("Authentication & Authorization"),
      description:
        gettext_noop("OAuth2 authentication, token scopes, and authorization for both APIs."),
      kind: :reference
    },
    "server-configuration" => %{
      title: gettext_noop("Server Configuration"),
      description:
        gettext_noop("Environment variables and configuration options for hosting Micelio."),
      kind: :reference
    }
  }

  # Read index files for each category at compile time
  @category_indexes Map.keys(@categories)
                    |> Map.new(fn category ->
                      index_path =
                        Application.app_dir(:micelio, "priv/docs/#{category}/_index.txt")

                      page_ids =
                        if File.exists?(index_path) do
                          index_path
                          |> File.read!()
                          |> String.split("\n", trim: true)
                          |> Enum.map(&String.trim/1)
                          |> Enum.reject(&(&1 == "" or String.starts_with?(&1, "#")))
                        else
                          []
                        end

                      {category, page_ids}
                    end)

  # Merge NimblePublisher pages with gRPC-generated pages
  @all_pages @pages ++ Micelio.Docs.GrpcDocs.pages()

  # Group pages by category and sort by index order
  # Pages not in the index are placed at the end, sorted alphabetically by id
  @pages_by_category @all_pages
                     |> Enum.group_by(& &1.category)
                     |> Map.new(fn {category, pages} ->
                       index = Map.get(@category_indexes, category, [])

                       index_positions =
                         index
                         |> Enum.with_index()
                         |> Map.new()

                       sorted_pages =
                         Enum.sort_by(pages, fn page ->
                           case Map.get(index_positions, page.id) do
                             nil -> {1, page.id}
                             pos -> {0, pos}
                           end
                         end)

                       {category, sorted_pages}
                     end)

  @doc """
  Returns all documentation pages sorted by category and index order.
  """
  def all_pages do
    @categories
    |> Map.keys()
    |> Enum.flat_map(&pages_by_category/1)
  end

  @doc """
  Returns all pages for a given category, sorted by index order.
  """
  def pages_by_category(category) when is_binary(category) do
    Map.get(@pages_by_category, category, [])
  end

  @doc """
  Returns metadata for all supported categories.
  """
  def categories do
    @categories
  end

  @doc """
  Returns categories filtered by kind (:guide or :reference).
  """
  def categories_by_kind(kind) when kind in [:guide, :reference] do
    @categories
    |> Enum.filter(fn {_id, info} -> info[:kind] == kind end)
    |> Map.new()
  end

  @doc """
  Returns metadata for a specific category.
  """
  def get_category(category) when is_binary(category) do
    Map.get(@categories, category)
  end

  @doc """
  Gets a page by category and ID.
  Raises if not found.
  """
  def get_page!(category, id) when is_binary(category) and is_binary(id) do
    category
    |> pages_by_category()
    |> Enum.find(&(&1.id == id)) ||
      raise "doc page with category=#{category} id=#{id} not found"
  end

  @doc """
  Searches documentation pages using fuzzy matching.

  Returns a list of `{page, score}` tuples sorted by relevance (highest score first).
  Only returns results with a score above the threshold.
  """
  def search(query) when is_binary(query) do
    query = query |> String.trim() |> String.downcase()

    if String.length(query) < 2 do
      []
    else
      @all_pages
      |> Enum.map(fn page ->
        score = calculate_search_score(page, query)
        {page, score}
      end)
      |> Enum.filter(fn {_page, score} -> score > 0 end)
      |> Enum.sort_by(fn {_page, score} -> score end, :desc)
    end
  end

  defp calculate_search_score(page, query) do
    title_score = fuzzy_score(String.downcase(page.title), query) * 3.0
    description_score = fuzzy_score(String.downcase(page.description), query) * 2.0
    body_score = fuzzy_score(String.downcase(strip_html(page.body)), query) * 1.0

    title_score + description_score + body_score
  end

  # Simple fuzzy matching algorithm
  # Returns a score between 0 and 1 based on how well the query matches the text
  defp fuzzy_score(text, query) do
    cond do
      # Exact match gets highest score
      String.contains?(text, query) ->
        1.0

      # Check if all words in query appear in text
      query_words_match?(text, query) ->
        0.8

      # Subsequence match (characters appear in order)
      subsequence_match?(text, query) ->
        0.5

      # Partial word matches
      partial_match_score(text, query) > 0 ->
        partial_match_score(text, query) * 0.3

      true ->
        0.0
    end
  end

  defp query_words_match?(text, query) do
    words = String.split(query, ~r/\s+/, trim: true)

    Enum.all?(words, fn word ->
      String.contains?(text, word)
    end)
  end

  defp subsequence_match?(text, query) do
    query_chars = String.graphemes(query)
    text_chars = String.graphemes(text)
    subsequence_match_chars?(text_chars, query_chars)
  end

  defp subsequence_match_chars?(_text_chars, []), do: true
  defp subsequence_match_chars?([], _query_chars), do: false

  defp subsequence_match_chars?([text_char | text_rest], [query_char | query_rest] = query_chars) do
    if text_char == query_char do
      subsequence_match_chars?(text_rest, query_rest)
    else
      subsequence_match_chars?(text_rest, query_chars)
    end
  end

  defp partial_match_score(text, query) do
    words = String.split(query, ~r/\s+/, trim: true)
    matches = Enum.count(words, fn word -> String.contains?(text, word) end)

    if Enum.empty?(words) do
      0.0
    else
      matches / length(words)
    end
  end

  defp strip_html(html) do
    html
    |> String.replace(~r/<[^>]+>/, " ")
    |> String.replace(~r/\s+/, " ")
    |> String.trim()
  end
end
