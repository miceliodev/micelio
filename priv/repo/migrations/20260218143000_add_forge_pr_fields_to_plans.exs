defmodule Micelio.Repo.Migrations.AddForgePrFieldsToPlans do
  use Ecto.Migration

  def change do
    execute("""
    DO $$
    BEGIN
      IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_schema = 'public'
          AND table_name = 'plans'
          AND column_name = 'forge_branch_name'
      ) THEN
        ALTER TABLE plans ADD COLUMN forge_branch_name varchar(255);
      END IF;
      IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_schema = 'public'
          AND table_name = 'plans'
          AND column_name = 'forge_pr_provider'
      ) THEN
        ALTER TABLE plans ADD COLUMN forge_pr_provider varchar(32);
      END IF;
      IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_schema = 'public'
          AND table_name = 'plans'
          AND column_name = 'forge_pr_number'
      ) THEN
        ALTER TABLE plans ADD COLUMN forge_pr_number integer;
      END IF;
      IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_schema = 'public'
          AND table_name = 'plans'
          AND column_name = 'forge_pr_url'
      ) THEN
        ALTER TABLE plans ADD COLUMN forge_pr_url varchar(1024);
      END IF;
      IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_schema = 'public'
          AND table_name = 'plans'
          AND column_name = 'forge_pr_state'
      ) THEN
        ALTER TABLE plans ADD COLUMN forge_pr_state varchar(32);
      END IF;
      IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_schema = 'public'
          AND table_name = 'plans'
          AND column_name = 'forge_pr_draft'
      ) THEN
        ALTER TABLE plans ADD COLUMN forge_pr_draft boolean DEFAULT true NOT NULL;
      END IF;
      IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_schema = 'public'
          AND table_name = 'plans'
          AND column_name = 'forge_pr_synced_at'
      ) THEN
        ALTER TABLE plans ADD COLUMN forge_pr_synced_at timestamp;
      END IF;
      IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_schema = 'public'
          AND table_name = 'plans'
          AND column_name = 'forge_pr_metadata'
      ) THEN
        ALTER TABLE plans ADD COLUMN forge_pr_metadata jsonb DEFAULT '{}'::jsonb NOT NULL;
      END IF;
    END
    $$;
    """)

    execute(
      "CREATE INDEX IF NOT EXISTS plans_forge_pr_provider_forge_pr_number_index ON plans (forge_pr_provider, forge_pr_number);"
    )
  end
end
