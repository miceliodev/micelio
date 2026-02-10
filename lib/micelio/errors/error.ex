defmodule Micelio.Errors.Error do
  use Ecto.Schema

  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @kinds [:exception, :oban_job, :liveview_crash, :plug_error, :agent_crash]
  @severities [:debug, :info, :warning, :error, :critical]

  schema "errors" do
    field :fingerprint, :string
    field :kind, Ecto.Enum, values: @kinds
    field :message, :string
    field :stacktrace, :string
    field :metadata, :map, default: %{}
    field :context, :map, default: %{}
    field :severity, Ecto.Enum, values: @severities, default: :error
    field :occurred_at, :utc_datetime
    field :resolved_at, :utc_datetime
    field :occurrence_count, :integer, default: 1
    field :first_seen_at, :utc_datetime
    field :last_seen_at, :utc_datetime

    belongs_to :user, Micelio.Accounts.User
    belongs_to :repository, Micelio.Repositories.Repository
    belongs_to :resolved_by, Micelio.Accounts.User, foreign_key: :resolved_by_id

    timestamps(type: :utc_datetime)
  end

  def changeset(error, attrs) do
    error
    |> cast(attrs, [
      :fingerprint,
      :kind,
      :message,
      :stacktrace,
      :metadata,
      :context,
      :severity,
      :occurred_at,
      :user_id,
      :repository_id,
      :resolved_at,
      :resolved_by_id,
      :occurrence_count,
      :first_seen_at,
      :last_seen_at
    ])
    |> validate_required([
      :fingerprint,
      :kind,
      :message,
      :severity,
      :occurred_at,
      :occurrence_count,
      :first_seen_at,
      :last_seen_at
    ])
    |> validate_number(:occurrence_count, greater_than: 0)
    |> assoc_constraint(:user)
    |> assoc_constraint(:repository)
    |> assoc_constraint(:resolved_by)
  end

  def kinds, do: @kinds
  def severities, do: @severities
end
