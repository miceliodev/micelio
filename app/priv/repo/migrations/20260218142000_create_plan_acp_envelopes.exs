defmodule Micelio.Repo.Migrations.CreatePlanAcpEnvelopes do
  use Ecto.Migration

  def change do
    execute("""
    CREATE TABLE IF NOT EXISTS plan_acp_envelopes (
      id uuid PRIMARY KEY NOT NULL,
      plan_id uuid NOT NULL REFERENCES plans(id) ON DELETE CASCADE,
      direction text NOT NULL,
      event_type text NOT NULL,
      payload jsonb NOT NULL DEFAULT '{}'::jsonb,
      sequence integer NOT NULL,
      inserted_at timestamp(0) NOT NULL,
      updated_at timestamp(0) NOT NULL
    );
    """)

    execute("""
    CREATE INDEX IF NOT EXISTS plan_acp_envelopes_plan_id_index
      ON plan_acp_envelopes (plan_id);
    """)

    execute("""
    CREATE INDEX IF NOT EXISTS plan_acp_envelopes_plan_id_sequence_index
      ON plan_acp_envelopes (plan_id, sequence);
    """)
  end
end
