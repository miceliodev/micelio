defmodule Micelio.Errors.RetentionSettings do
  use Ecto.Schema

  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "error_retention_settings" do
    field :resolved_retention_days, :integer, default: 30
    field :unresolved_retention_days, :integer, default: 90
    field :archive_enabled, :boolean, default: false

    timestamps(type: :utc_datetime)
  end

  def changeset(settings, attrs) do
    settings
    |> cast(attrs, [:resolved_retention_days, :unresolved_retention_days, :archive_enabled])
    |> validate_number(:resolved_retention_days, greater_than: 0)
    |> validate_number(:unresolved_retention_days, greater_than: 0)
  end
end
