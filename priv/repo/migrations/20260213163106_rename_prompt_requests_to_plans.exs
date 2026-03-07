defmodule Micelio.Repo.Migrations.RenamePromptRequestsToPlans do
  use Ecto.Migration

  def change do
    execute("""
    DO $$
    BEGIN
      IF to_regclass('public.prompt_requests') IS NOT NULL THEN
        ALTER TABLE prompt_requests RENAME TO plans;
      END IF;

      IF to_regclass('public.prompt_suggestions') IS NOT NULL THEN
        ALTER TABLE prompt_suggestions RENAME TO plan_suggestions;
      END IF;

      IF to_regclass('public.prompt_templates') IS NOT NULL THEN
        ALTER TABLE prompt_templates RENAME TO plan_templates;
      END IF;

      IF EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_schema = 'public'
          AND table_name = 'plans'
          AND column_name = 'parent_prompt_request_id'
      ) THEN
        ALTER TABLE plans RENAME COLUMN parent_prompt_request_id TO parent_plan_id;
      END IF;

      IF EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_schema = 'public'
          AND table_name = 'plans'
          AND column_name = 'prompt_template_id'
      ) THEN
        ALTER TABLE plans RENAME COLUMN prompt_template_id TO plan_template_id;
      END IF;

      IF EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_schema = 'public'
          AND table_name = 'plan_suggestions'
          AND column_name = 'prompt_request_id'
      ) THEN
        ALTER TABLE plan_suggestions RENAME COLUMN prompt_request_id TO plan_id;
      END IF;

      IF EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_schema = 'public'
          AND table_name = 'ai_token_earnings'
          AND column_name = 'prompt_request_id'
      ) THEN
        ALTER TABLE ai_token_earnings RENAME COLUMN prompt_request_id TO plan_id;
      END IF;

      IF EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_schema = 'public'
          AND table_name = 'ai_token_task_budgets'
          AND column_name = 'prompt_request_id'
      ) THEN
        ALTER TABLE ai_token_task_budgets RENAME COLUMN prompt_request_id TO plan_id;
      END IF;

      IF EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_schema = 'public'
          AND table_name = 'validation_runs'
          AND column_name = 'prompt_request_id'
      ) THEN
        ALTER TABLE validation_runs RENAME COLUMN prompt_request_id TO plan_id;
      END IF;

      CREATE TABLE IF NOT EXISTS plan_messages (
        id uuid PRIMARY KEY NOT NULL,
        plan_id uuid NOT NULL REFERENCES plans(id) ON DELETE CASCADE,
        role varchar(20) NOT NULL,
        content text,
        model varchar(120),
        author varchar(255),
        agent varchar(50),
        tool_name varchar(255),
        tool_input jsonb,
        tool_output jsonb,
        status varchar(20) NOT NULL DEFAULT 'complete',
        token_count integer,
        sequence integer NOT NULL,
        inserted_at timestamp(0) NOT NULL,
        updated_at timestamp(0) NOT NULL
      );

      CREATE INDEX IF NOT EXISTS plan_messages_plan_id_index ON plan_messages (plan_id);
      CREATE INDEX IF NOT EXISTS plan_messages_plan_id_sequence_index ON plan_messages (plan_id, sequence);

      IF to_regclass('public.plans') IS NOT NULL THEN
        ALTER TABLE plans
          ADD COLUMN IF NOT EXISTS agent varchar(50);
        ALTER TABLE plans
          ADD COLUMN IF NOT EXISTS agent_model varchar(120);
        ALTER TABLE plans
          ADD COLUMN IF NOT EXISTS agent_status varchar(20) DEFAULT 'idle' NOT NULL;
      END IF;
    END
    $$;
    """)
  end
end
