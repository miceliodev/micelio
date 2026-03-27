defmodule Micelio.Repo.Migrations.FixAiTokenEarningsPlanSuggestionFields do
  use Ecto.Migration

  def up do
    execute("""
    DO $$
    BEGIN
      UPDATE ai_token_earnings
      SET reason = 'plan_suggestion_submitted'
      WHERE reason = 'prompt_suggestion_submitted';

      IF EXISTS (
        SELECT 1
        FROM information_schema.columns
        WHERE table_schema = 'public'
          AND table_name = 'ai_token_earnings'
          AND column_name = 'prompt_suggestion_id'
      ) THEN
        ALTER TABLE ai_token_earnings
          RENAME COLUMN prompt_suggestion_id TO plan_suggestion_id;
      END IF;
    END
    $$;
    """)

    execute("""
    DROP INDEX IF EXISTS ai_token_earnings_prompt_suggestion_id_index;
    """)

    execute("""
    CREATE INDEX IF NOT EXISTS ai_token_earnings_plan_suggestion_id_index
      ON ai_token_earnings (plan_suggestion_id);
    """)

    execute("""
    DROP INDEX IF EXISTS ai_token_earnings_prompt_request_id_user_id_reason_index;
    """)

    execute("""
    CREATE UNIQUE INDEX IF NOT EXISTS ai_token_earnings_plan_id_user_id_reason_index
      ON ai_token_earnings (plan_id, user_id, reason);
    """)
  end

  def down do
    execute("""
    DO $$
    BEGIN
      DROP INDEX IF EXISTS ai_token_earnings_plan_id_user_id_reason_index;
      DROP INDEX IF EXISTS ai_token_earnings_plan_suggestion_id_index;

      IF EXISTS (
        SELECT 1
        FROM information_schema.columns
        WHERE table_schema = 'public'
          AND table_name = 'ai_token_earnings'
          AND column_name = 'plan_suggestion_id'
      ) THEN
        ALTER TABLE ai_token_earnings
          RENAME COLUMN plan_suggestion_id TO prompt_suggestion_id;
      END IF;
    END
    $$;
    """)

    execute("""
    UPDATE ai_token_earnings
    SET reason = 'prompt_suggestion_submitted'
    WHERE reason = 'plan_suggestion_submitted';
    """)

    execute("""
    CREATE INDEX IF NOT EXISTS ai_token_earnings_prompt_suggestion_id_index
      ON ai_token_earnings (prompt_suggestion_id);
    """)

    execute("""
    CREATE UNIQUE INDEX IF NOT EXISTS ai_token_earnings_prompt_request_id_user_id_reason_index
      ON ai_token_earnings (plan_id, user_id, reason);
    """)
  end
end
