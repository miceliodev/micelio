defmodule Micelio.Blog do
  @moduledoc """
  The Blog context for managing blog posts using NimblePublisher.

  Posts are organized by locale in the filesystem:
  - priv/posts/en/2026/01-14-post-id.md (English, default)
  - priv/posts/ja/2026/01-14-post-id.md (Japanese)
  - etc.

  If a translation is not available, the English version is used as fallback.
  """
  use NimblePublisher,
    # Ensure syntax highlighting aliases are registered before NimblePublisher compiles
    build: Micelio.Blog.Post,
    from: Application.app_dir(:micelio, "priv/posts/**/*.md"),
    as: :posts,
    highlighters: [:makeup_elixir, :makeup_erlang, :makeup_syntect]

  require Micelio.SyntaxHighlighting

  @supported_locales ~w(en ko zh_CN zh_TW ja)

  # Use NimblePublisher to build all posts from all locales

  # The @posts variable is first populated at compilation time.
  # Group posts by locale
  @posts_by_locale @posts
                   |> Enum.group_by(& &1.locale)
                   |> Map.new(fn {locale, posts} ->
                     {locale, Enum.sort_by(posts, & &1.date, {:desc, Date})}
                   end)

  # Default English posts sorted by date
  @english_posts Map.get(@posts_by_locale, "en", [])

  # Let's also get all tags from English posts (primary source)
  @tags @english_posts |> Enum.flat_map(& &1.tags) |> Enum.uniq() |> Enum.sort()

  def supported_locales, do: @supported_locales

  @doc """
  Returns all posts for a given locale, falling back to English for missing translations.
  """
  def all_posts(locale \\ "en") do
    locale_posts = Map.get(@posts_by_locale, locale, [])
    locale_post_ids = MapSet.new(locale_posts, & &1.id)

    # Get English posts that don't have a translation in this locale
    english_fallbacks =
      @english_posts
      |> Enum.reject(&MapSet.member?(locale_post_ids, &1.id))

    (locale_posts ++ english_fallbacks)
    |> Enum.sort_by(& &1.date, {:desc, Date})
  end

  def all_tags, do: @tags

  def recent_posts(count \\ 5, locale \\ "en") do
    Enum.take(all_posts(locale), count)
  end

  @doc """
  Gets a post by ID for the given locale, falling back to English if not found.
  """
  def get_post_by_id!(id, locale \\ "en") do
    # Try locale-specific post first
    locale_posts = Map.get(@posts_by_locale, locale, [])

    # Fall back to English
    Enum.find(locale_posts, &(&1.id == id)) ||
      Enum.find(@english_posts, &(&1.id == id)) ||
      raise "post with id=#{id} not found"
  end

  def get_posts_by_tag!(tag, locale \\ "en") do
    case Enum.filter(all_posts(locale), &(tag in &1.tags)) do
      [] -> raise "posts with tag=#{tag} not found"
      posts -> posts
    end
  end
end
