defmodule Micelio.Repo.Migrations.FixAiTokenEarningsPlanSuggestionFields do
  use Ecto.Migration

  def up do
    execute("""
    UPDATE ai_token_earnings
    SET reason = 'plan_suggestion_submitted'
    WHERE reason = 'prompt_suggestion_submitted'
    """)

    rename table(:ai_token_earnings), :prompt_suggestion_id, to: :plan_suggestion_id

    drop_if_exists index(:ai_token_earnings, [:prompt_suggestion_id])
    create index(:ai_token_earnings, [:plan_suggestion_id])

    drop_if_exists index(:ai_token_earnings, [:plan_id, :user_id, :reason],
                     name: :ai_token_earnings_prompt_request_id_user_id_reason_index
                   )

    create unique_index(:ai_token_earnings, [:plan_id, :user_id, :reason],
             name: :ai_token_earnings_plan_id_user_id_reason_index
           )
  end

  def down do
    drop_if_exists index(:ai_token_earnings, [:plan_id, :user_id, :reason],
                     name: :ai_token_earnings_plan_id_user_id_reason_index
                   )

    drop_if_exists index(:ai_token_earnings, [:plan_suggestion_id])

    rename table(:ai_token_earnings), :plan_suggestion_id, to: :prompt_suggestion_id

    create index(:ai_token_earnings, [:prompt_suggestion_id])

    create unique_index(:ai_token_earnings, [:plan_id, :user_id, :reason],
             name: :ai_token_earnings_prompt_request_id_user_id_reason_index
           )

    execute("""
    UPDATE ai_token_earnings
    SET reason = 'prompt_suggestion_submitted'
    WHERE reason = 'plan_suggestion_submitted'
    """)
  end
end
