defmodule Micelio.Repo.Migrations.UpdateAiTokenEarningsForSuggestions do
  use Ecto.Migration

  def change do
    alter table(:ai_token_earnings) do
      add :prompt_suggestion_id,
          references(:prompt_suggestions, type: :binary_id, on_delete: :delete_all)
    end

    drop_if_exists unique_index(:ai_token_earnings, [:prompt_request_id])

    create index(:ai_token_earnings, [:prompt_suggestion_id])

    create unique_index(:ai_token_earnings, [:prompt_request_id, :user_id, :reason],
             name: :ai_token_earnings_prompt_request_id_user_id_reason_index
           )
  end
end
