defmodule Micelio.Sessions.SessionChange do
  @moduledoc """
  Represents a file change within a session.

  In mic, we don't track "commits" - we track changes as part of sessions.
  Each change captures:
  - What file was modified (file_path)
  - How it was modified (change_type: added, modified, deleted)
  - The actual content or reference to it (content or storage_key)
  - Context about the change (metadata)

  This aligns with the mic philosophy: "Git tracks what. mic tracks why."
  The session provides the "why", and changes provide the "what".
  """
  use Micelio.Schema

  import Ecto.Changeset

  @change_types ["added", "modified", "deleted"]

  schema "session_changes" do
    field :file_path, :string
    field :change_type, :string
    field :storage_key, :string
    field :content, :string
    field :metadata, :map, default: %{}

    belongs_to :session, Micelio.Sessions.Session

    timestamps()
  end

  @doc false
  def changeset(change, attrs) do
    change
    |> cast(attrs, [:session_id, :file_path, :change_type, :storage_key, :content, :metadata])
    |> validate_required([:session_id, :file_path, :change_type])
    |> validate_inclusion(:change_type, @change_types)
    |> validate_content_or_storage_key()
  end

  defp validate_content_or_storage_key(changeset) do
    require Logger

    change_type = get_field(changeset, :change_type)
    content = get_field(changeset, :content)
    storage_key = get_field(changeset, :storage_key)
    file_path = get_field(changeset, :file_path)

    # Deleted files don't need content or storage key
    if change_type == "deleted" do
      changeset
    else
      # For added/modified files, we need either content or storage_key
      if is_nil(content) && is_nil(storage_key) do
        Logger.warning(
          "File #{inspect(file_path)} has nil content and nil storage_key, change_type=#{inspect(change_type)}"
        )

        add_error(
          changeset,
          :content,
          "must provide either content or storage_key for non-deleted files"
        )
      else
        changeset
      end
    end
  end

  @doc """
  Returns the list of valid change types.
  """
  def change_types, do: @change_types
end
