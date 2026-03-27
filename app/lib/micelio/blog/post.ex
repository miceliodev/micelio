defmodule Micelio.Blog.Post do
  @moduledoc """
  A blog post struct for NimblePublisher.

  Posts are organized by locale in the filesystem:
  - priv/posts/en/2026/01-14-post-id.md
  - priv/posts/ja/2026/01-14-post-id.md

  The locale is extracted from the directory structure.
  """

  alias Micelio.Blog.People

  @enforce_keys [:id, :author, :title, :body, :description, :tags, :date, :locale]
  defstruct [:id, :author, :title, :body, :description, :tags, :date, :locale]

  @supported_locales ~w(en ko zh_CN zh_TW ja)

  def build(filename, attrs, body) do
    parts = filename |> Path.rootname() |> Path.split()

    # Extract locale from path - look for a supported locale in the path
    # Path structure: .../priv/posts/en/2026/01-14-post-id.md or .../priv/posts/2026/01-14-post-id.md
    {locale, year, month_day_id} = extract_locale_and_date_parts(parts)

    [month, day, id] = String.split(month_day_id, "-", parts: 3)
    date = Date.from_iso8601!("#{year}-#{month}-#{day}")

    attrs = normalize_attrs!(attrs)

    struct!(
      __MODULE__,
      [
        id: id,
        date: date,
        body: add_heading_anchors(body),
        locale: locale
      ] ++ Map.to_list(attrs)
    )
  end

  # Extract locale from path parts
  # Supports: priv/posts/en/2026/01-14-id.md (with locale) or priv/posts/2026/01-14-id.md (without)
  defp extract_locale_and_date_parts(parts) do
    # Take last 3 parts which could be [locale, year, filename] or [posts, year, filename]
    case Enum.take(parts, -3) do
      [locale, year, filename] when locale in @supported_locales ->
        {locale, year, filename}

      _ ->
        # Fallback: no locale prefix, default to "en"
        [year, filename] = Enum.take(parts, -2)
        {"en", year, filename}
    end
  end

  defp normalize_attrs!(%{author: author_id} = attrs) when is_atom(author_id) do
    _ = People.get!(author_id)
    # Remove model field if present (no longer used)
    Map.delete(attrs, :model)
  end

  defp normalize_attrs!(%{author: author_name} = _attrs) when is_binary(author_name) do
    raise ArgumentError,
          "blog post author must be one of #{People.all() |> Enum.map(& &1.id) |> inspect()}, got: #{inspect(author_name)}"
  end

  defp add_heading_anchors(html) do
    Regex.replace(
      ~r/<(h[1-6])>(.*?)<\/h[1-6]>/s,
      html,
      fn _match, tag, content ->
        text = Regex.replace(~r/<[^>]+>/, content, "")
        slug = slugify(text)

        ~s(<#{tag} id="#{slug}"><a href="##{slug}" class="heading-anchor" aria-label="Link to #{text}">#{content}</a></#{tag}>)
      end
    )
  end

  defp slugify(text) do
    text
    |> String.downcase()
    |> String.replace(~r/[^\w\s-]/u, "")
    |> String.trim()
    |> String.replace(~r/\s+/, "-")
  end
end
