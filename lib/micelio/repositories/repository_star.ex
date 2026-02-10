defmodule Micelio.Repositories.RepositoryStar do
  use Micelio.Schema

  import Ecto.Changeset

  schema "repository_stars" do
    belongs_to :repository, Micelio.Repositories.Repository
    belongs_to :user, Micelio.Accounts.User

    timestamps(type: :utc_datetime)
  end

  @doc """
  Changeset for starring a repository.
  """
  def changeset(repository_star, attrs) do
    repository_star
    |> cast(attrs, [:repository_id, :user_id])
    |> validate_required([:repository_id, :user_id])
    |> assoc_constraint(:repository)
    |> assoc_constraint(:user)
    |> unique_constraint([:user_id, :repository_id],
      name: :repository_stars_user_id_repository_id_index,
      message: "has already been starred"
    )
  end
end
