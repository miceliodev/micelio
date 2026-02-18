defmodule Micelio.Repo.Migrations.CreatePlanAcpEnvelopes do
  use Ecto.Migration

  def change do
    create table(:plan_acp_envelopes, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :plan_id, references(:plans, type: :binary_id, on_delete: :delete_all), null: false
      add :direction, :string, size: 32, null: false
      add :event_type, :string, size: 120, null: false
      add :payload, :map, null: false, default: %{}
      add :sequence, :integer, null: false

      timestamps(type: :utc_datetime)
    end

    create index(:plan_acp_envelopes, [:plan_id])
    create index(:plan_acp_envelopes, [:plan_id, :sequence])
  end
end
