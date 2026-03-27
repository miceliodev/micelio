defmodule Micelio.Errors.NotificationLog do
  use Ecto.Schema

  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @reasons [:new_error, :threshold, :critical]

  schema "error_notifications" do
    field :fingerprint, :string
    field :severity, Ecto.Enum, values: Micelio.Errors.Error.severities()
    field :reason, Ecto.Enum, values: @reasons
    field :channels, {:array, :string}, default: []

    belongs_to :error, Micelio.Errors.Error

    timestamps(type: :utc_datetime)
  end

  def changeset(notification, attrs) do
    notification
    |> cast(attrs, [:fingerprint, :severity, :reason, :channels, :error_id])
    |> validate_required([:fingerprint, :severity, :reason])
    |> validate_length(:channels, min: 0)
    |> assoc_constraint(:error)
  end

  def reasons, do: @reasons
end
