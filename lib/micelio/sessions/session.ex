defmodule Micelio.Sessions.Session do
  use Micelio.Schema

  import Ecto.Changeset

  schema "sessions" do
    field :session_id, :string
    field :goal, :string
    field :status, :string, default: "active"
    field :conversation, {:array, :map}, default: []
    field :decisions, {:array, :map}, default: []
    field :metadata, :map, default: %{}
    field :started_at, :utc_datetime
    field :landed_at, :utc_datetime

    belongs_to :repository, Micelio.Repositories.Repository
    belongs_to :user, Micelio.Accounts.User
    has_many :changes, Micelio.Sessions.SessionChange
    has_one :prompt_request, Micelio.PromptRequests.PromptRequest, foreign_key: :session_id

    timestamps()
  end

  @doc false
  def changeset(session, attrs) do
    session
    |> cast(attrs, [
      :session_id,
      :goal,
      :status,
      :repository_id,
      :user_id,
      :conversation,
      :decisions,
      :metadata,
      :started_at,
      :landed_at
    ])
    |> validate_required([:session_id, :goal, :repository_id, :user_id])
    |> validate_inclusion(:status, ["active", "landed", "abandoned"])
    |> unique_constraint(:session_id)
  end

  @doc false
  def create_changeset(session, attrs) do
    started_at =
      case attrs[:started_at] do
        nil -> DateTime.utc_now() |> DateTime.truncate(:second)
        dt -> dt
      end

    session
    |> changeset(attrs)
    |> put_change(:status, "active")
    |> put_change(:started_at, started_at)
  end

  @doc false
  def land_changeset(session, attrs \\ %{}) do
    session
    |> changeset(attrs)
    |> put_change(:status, "landed")
    |> put_change(:landed_at, DateTime.utc_now() |> DateTime.truncate(:second))
  end

  @doc false
  def abandon_changeset(session) do
    session
    |> change()
    |> put_change(:status, "abandoned")
    |> put_change(:landed_at, DateTime.utc_now() |> DateTime.truncate(:second))
  end

  # Agent-trace attribution accessors (stored in metadata JSONB)

  @contributor_types ["human", "ai", "mixed", "unknown"]

  def contributor_type(%__MODULE__{metadata: %{"contributor_type" => type}})
      when type in @contributor_types, do: type

  def contributor_type(_session), do: "unknown"

  def model_id(%__MODULE__{metadata: %{"model_id" => id}}) when is_binary(id) and id != "", do: id

  def model_id(_session), do: nil

  def tool_name(%__MODULE__{metadata: %{"tool_name" => name}})
      when is_binary(name) and name != "", do: name

  def tool_name(_session), do: nil

  def tool_version(%__MODULE__{metadata: %{"tool_version" => version}})
      when is_binary(version) and version != "", do: version

  def tool_version(_session), do: nil

  def ai_session?(%__MODULE__{} = session), do: contributor_type(session) in ["ai", "mixed"]
end
