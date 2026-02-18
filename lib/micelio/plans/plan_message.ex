defmodule Micelio.Plans.PlanMessage do
  use Micelio.Schema

  import Ecto.Changeset

  schema "plan_messages" do
    field :role, :string
    field :content, :string
    field :model, :string
    field :author, :string
    field :agent, :string
    field :tool_name, :string
    field :tool_input, :map
    field :tool_output, :map
    field :status, :string, default: "complete"
    field :token_count, :integer
    field :sequence, :integer

    belongs_to :plan, Micelio.Plans.Plan

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(message, attrs) do
    message
    |> cast(attrs, [
      :plan_id,
      :role,
      :content,
      :model,
      :author,
      :agent,
      :tool_name,
      :tool_input,
      :tool_output,
      :status,
      :token_count,
      :sequence
    ])
    |> validate_required([:role, :sequence, :status])
    |> validate_length(:role, max: 20)
    |> validate_length(:model, max: 120)
    |> validate_length(:author, max: 255)
    |> validate_length(:agent, max: 50)
    |> validate_length(:tool_name, max: 255)
    |> validate_length(:status, max: 20)
  end
end
