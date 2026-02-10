defmodule Micelio.AgentInfra.VolumeMount do
  @moduledoc """
  Defines mountable volumes for agent VM provisioning.
  """

  use Ecto.Schema

  import Ecto.Changeset

  @primary_key false
  embedded_schema do
    field :name, :string
    field :source, :string
    field :target, :string
    field :access, :string, default: "rw"
    field :type, :string, default: "volume"
    field :read_only, :boolean, virtual: true
  end

  @type t :: %__MODULE__{
          name: String.t() | nil,
          source: String.t() | nil,
          target: String.t() | nil,
          access: String.t() | nil,
          type: String.t() | nil,
          read_only: boolean() | nil
        }

  @doc """
  Builds a changeset for a volume mount.
  """
  def changeset(mount, attrs) do
    mount
    |> cast(attrs, [:name, :source, :target, :access, :type, :read_only])
    |> normalize_access()
    |> update_change(:access, &normalize_access_value/1)
    |> validate_required([:name, :source, :target, :access, :type])
    |> validate_length(:name, min: 1, max: 64)
    |> validate_format(:name, ~r/^[a-z0-9][a-z0-9-_]*$/i,
      message:
        "must start with a letter or number and use only alphanumerics, dashes, or underscores"
    )
    |> validate_inclusion(:access, ["ro", "rw"])
    |> validate_inclusion(:type, ["volume", "bind"])
    |> validate_target_absolute()
    |> validate_source_path()
  end

  defp normalize_access(changeset) do
    case get_change(changeset, :read_only) do
      nil -> changeset
      true -> put_change(changeset, :access, "ro")
      false -> put_change(changeset, :access, "rw")
    end
  end

  defp normalize_access_value(access) when is_binary(access) do
    case String.downcase(access) do
      "ro" -> "ro"
      "read-only" -> "ro"
      "read_only" -> "ro"
      "readonly" -> "ro"
      "rw" -> "rw"
      "read-write" -> "rw"
      "read_write" -> "rw"
      "readwrite" -> "rw"
      value -> value
    end
  end

  defp normalize_access_value(value), do: value

  defp validate_target_absolute(changeset) do
    validate_change(changeset, :target, fn :target, target ->
      if String.starts_with?(target, "/") do
        []
      else
        [target: "must be an absolute path"]
      end
    end)
  end

  defp validate_source_path(changeset) do
    validate_change(changeset, :source, fn :source, source ->
      source = String.trim(source)
      type = get_field(changeset, :type, "volume")

      cond do
        source == "" ->
          [source: "can't be blank"]

        type == "bind" and not String.starts_with?(source, "/") ->
          [source: "must be an absolute path for bind mounts"]

        true ->
          []
      end
    end)
  end
end
