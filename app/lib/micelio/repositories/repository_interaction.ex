defmodule Micelio.Repositories.RepositoryInteraction do
  use Micelio.Schema

  import Ecto.Changeset

  schema "repository_interactions" do
    field :last_interacted_at, :utc_datetime
    field :interaction_count, :integer, default: 0
    field :last_interaction_type, :string

    belongs_to :user, Micelio.Accounts.User
    belongs_to :repository, Micelio.Repositories.Repository

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(interaction, attrs) do
    interaction
    |> cast(attrs, [
      :user_id,
      :repository_id,
      :last_interacted_at,
      :interaction_count,
      :last_interaction_type
    ])
    |> validate_required([:user_id, :repository_id, :last_interacted_at])
  end
end
