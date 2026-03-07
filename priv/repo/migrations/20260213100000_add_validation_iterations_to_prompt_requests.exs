defmodule Micelio.Repo.Migrations.AddValidationIterationsToPromptRequests do
  use Ecto.Migration

  def change do
    execute("""
    DO $$
    BEGIN
      IF to_regclass('public.prompt_requests') IS NOT NULL THEN
        ALTER TABLE prompt_requests
        ADD COLUMN IF NOT EXISTS validation_iterations integer DEFAULT 0 NOT NULL;
      ELSIF to_regclass('public.plans') IS NOT NULL THEN
        ALTER TABLE plans
        ADD COLUMN IF NOT EXISTS validation_iterations integer DEFAULT 0 NOT NULL;
      END IF;
    END
    $$;
    """)
  end
end
