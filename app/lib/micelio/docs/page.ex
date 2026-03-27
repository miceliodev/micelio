defmodule Micelio.Docs.Page do
  @moduledoc """
  A documentation page struct for NimblePublisher.

  Pages are organized by category in the filesystem:
  - priv/docs/auth/authentication.md
  - priv/docs/rest-api/api-reference.md

  The category is extracted from the directory structure.
  Page ordering is defined in `_index.txt` files within each category directory.
  """

  @enforce_keys [:id, :title, :description, :body, :category]
  defstruct [:id, :title, :description, :body, :category]

  @supported_categories ~w(hosters contributors shapers grpc rest-api auth)

  def build(filename, attrs, body) do
    parts = filename |> Path.rootname() |> Path.split()

    # Extract category and id from path
    # Path structure: .../priv/docs/auth/authentication.md
    {category, id} = extract_category_and_id(parts)

    struct!(
      __MODULE__,
      [
        id: id,
        category: category,
        body: body
      ] ++ Map.to_list(attrs)
    )
  end

  # Extract category and id from path parts
  # Supports: priv/docs/auth/filename.md
  defp extract_category_and_id(parts) do
    # Take last 2 parts which should be [category, filename]
    case Enum.take(parts, -2) do
      [category, filename] when category in @supported_categories ->
        {category, filename}

      _ ->
        raise ArgumentError,
              "Doc file must be in a supported category directory (#{inspect(@supported_categories)})"
    end
  end
end
