defmodule Micelio.PromptRequests.PromptTemplate do
  use Ecto.Schema

  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "prompt_templates" do
    field :name, :string
    field :description, :string
    field :prompt, :string
    field :system_prompt, :string
    field :category, :string
    field :approved_at, :utc_datetime

    belongs_to :created_by, Micelio.Accounts.User
    belongs_to :approved_by, Micelio.Accounts.User

    timestamps(type: :utc_datetime)
  end

  def changeset(prompt_template, attrs) do
    prompt_template
    |> cast(attrs, [:name, :description, :prompt, :system_prompt, :category])
    |> validate_required([:name, :prompt, :system_prompt])
    |> validate_length(:name, max: 120)
    |> validate_length(:category, max: 80)
    |> unique_constraint(:name)
    |> assoc_constraint(:created_by)
  end

  def approval_changeset(prompt_template, attrs) do
    prompt_template
    |> cast(attrs, [:approved_at, :approved_by_id])
    |> validate_required([:approved_at, :approved_by_id])
    |> assoc_constraint(:approved_by)
  end
end
