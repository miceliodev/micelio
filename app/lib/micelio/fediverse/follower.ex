defmodule Micelio.Fediverse.Follower do
  use Micelio.Schema

  import Ecto.Changeset

  schema "fediverse_followers" do
    field :actor, :string
    field :inbox, :string

    belongs_to :account, Micelio.Accounts.Account

    timestamps(type: :utc_datetime)
  end

  def changeset(follower, attrs) do
    follower
    |> cast(attrs, [:account_id, :actor, :inbox])
    |> validate_required([:account_id, :actor])
    |> assoc_constraint(:account)
    |> unique_constraint([:account_id, :actor], name: :fediverse_followers_account_id_actor_index)
  end
end
