defmodule Micelio.Repo.Migrations.RenameProjectsToRepositories do
  use Ecto.Migration

  def up do
    # Step 1: Drop existing indexes and constraints that will be renamed
    drop_if_exists index(:projects, [:organization_id])
    drop_if_exists index(:projects, [:forked_from_id])

    execute("DROP INDEX IF EXISTS projects_search_idx")
    execute("DROP INDEX IF EXISTS projects_organization_handle_index")

    drop_if_exists index(:project_stars, [:project_id])
    drop_if_exists index(:project_stars, [:user_id])

    execute("DROP INDEX IF EXISTS project_stars_user_id_project_id_index")

    drop_if_exists index(:project_interactions, [:user_id, :project_id])
    drop_if_exists index(:project_interactions, [:user_id, :last_interacted_at])

    drop_if_exists index(:project_access_tokens, [:project_id])
    drop_if_exists index(:project_access_tokens, [:user_id])
    drop_if_exists index(:project_access_tokens, [:token_hash])

    drop_if_exists index(:sessions, [:project_id])
    drop_if_exists index(:webhooks, [:project_id])
    drop_if_exists index(:prompt_requests, [:project_id])
    drop_if_exists index(:ai_token_pools, [:project_id])
    drop_if_exists index(:ai_token_contributions, [:project_id])
    drop_if_exists index(:ai_token_earnings, [:project_id])
    drop_if_exists index(:audit_logs, [:project_id])

    # Step 2: Rename tables
    rename table(:projects), to: table(:repositories)
    rename table(:project_stars), to: table(:repository_stars)
    rename table(:project_interactions), to: table(:repository_interactions)
    rename table(:project_access_tokens), to: table(:repository_access_tokens)

    # Step 3: Rename columns
    rename table(:repository_stars), :project_id, to: :repository_id
    rename table(:repository_interactions), :project_id, to: :repository_id
    rename table(:repository_access_tokens), :project_id, to: :repository_id
    rename table(:sessions), :project_id, to: :repository_id
    rename table(:webhooks), :project_id, to: :repository_id
    rename table(:prompt_requests), :project_id, to: :repository_id
    rename table(:ai_token_pools), :project_id, to: :repository_id
    rename table(:ai_token_contributions), :project_id, to: :repository_id
    rename table(:ai_token_earnings), :project_id, to: :repository_id
    rename table(:audit_logs), :project_id, to: :repository_id
    rename table(:errors), :project_id, to: :repository_id

    # Step 4: Recreate indexes with new names
    create index(:repositories, [:organization_id])
    create index(:repositories, [:forked_from_id])

    create unique_index(:repositories, [:organization_id, "lower(handle)"],
             name: :repositories_organization_handle_index
           )

    # Recreate FTS index
    execute("""
    CREATE INDEX repositories_search_idx ON repositories USING GIN (search_vector);
    """)

    create index(:repository_stars, [:repository_id])
    create index(:repository_stars, [:user_id])

    create unique_index(:repository_stars, [:user_id, :repository_id],
             name: :repository_stars_user_id_repository_id_index
           )

    create unique_index(:repository_interactions, [:user_id, :repository_id])
    create index(:repository_interactions, [:user_id, :last_interacted_at])

    create unique_index(:repository_access_tokens, [:token_hash])
    create index(:repository_access_tokens, [:repository_id])
    create index(:repository_access_tokens, [:user_id])

    create index(:sessions, [:repository_id])
    create index(:webhooks, [:repository_id])
    create index(:prompt_requests, [:repository_id])
    create unique_index(:ai_token_pools, [:repository_id])
    create index(:ai_token_contributions, [:repository_id])
    create index(:ai_token_earnings, [:repository_id])
    create index(:audit_logs, [:repository_id])
  end

  def down do
    # Step 1: Drop new indexes
    drop_if_exists index(:repositories, [:organization_id])
    drop_if_exists index(:repositories, [:forked_from_id])

    execute("DROP INDEX IF EXISTS repositories_search_idx")
    execute("DROP INDEX IF EXISTS repositories_organization_handle_index")

    drop_if_exists index(:repository_stars, [:repository_id])
    drop_if_exists index(:repository_stars, [:user_id])

    execute("DROP INDEX IF EXISTS repository_stars_user_id_repository_id_index")

    drop_if_exists index(:repository_interactions, [:user_id, :repository_id])
    drop_if_exists index(:repository_interactions, [:user_id, :last_interacted_at])

    drop_if_exists index(:repository_access_tokens, [:repository_id])
    drop_if_exists index(:repository_access_tokens, [:user_id])
    drop_if_exists index(:repository_access_tokens, [:token_hash])

    drop_if_exists index(:sessions, [:repository_id])
    drop_if_exists index(:webhooks, [:repository_id])
    drop_if_exists index(:prompt_requests, [:repository_id])
    drop_if_exists index(:ai_token_pools, [:repository_id])
    drop_if_exists index(:ai_token_contributions, [:repository_id])
    drop_if_exists index(:ai_token_earnings, [:repository_id])
    drop_if_exists index(:audit_logs, [:repository_id])

    # Step 2: Rename columns back
    rename table(:repository_stars), :repository_id, to: :project_id
    rename table(:repository_interactions), :repository_id, to: :project_id
    rename table(:repository_access_tokens), :repository_id, to: :project_id
    rename table(:sessions), :repository_id, to: :project_id
    rename table(:webhooks), :repository_id, to: :project_id
    rename table(:prompt_requests), :repository_id, to: :project_id
    rename table(:ai_token_pools), :repository_id, to: :project_id
    rename table(:ai_token_contributions), :repository_id, to: :project_id
    rename table(:ai_token_earnings), :repository_id, to: :project_id
    rename table(:audit_logs), :repository_id, to: :project_id
    rename table(:errors), :repository_id, to: :project_id

    # Step 3: Rename tables back
    rename table(:repositories), to: table(:projects)
    rename table(:repository_stars), to: table(:project_stars)
    rename table(:repository_interactions), to: table(:project_interactions)
    rename table(:repository_access_tokens), to: table(:project_access_tokens)

    # Step 4: Recreate original indexes
    create index(:projects, [:organization_id])
    create index(:projects, [:forked_from_id])

    create unique_index(:projects, [:organization_id, "lower(handle)"],
             name: :projects_organization_handle_index
           )

    execute("""
    CREATE INDEX projects_search_idx ON projects USING GIN (search_vector);
    """)

    create index(:project_stars, [:project_id])
    create index(:project_stars, [:user_id])

    create unique_index(:project_stars, [:user_id, :project_id],
             name: :project_stars_user_id_project_id_index
           )

    create unique_index(:project_interactions, [:user_id, :project_id])
    create index(:project_interactions, [:user_id, :last_interacted_at])

    create unique_index(:project_access_tokens, [:token_hash])
    create index(:project_access_tokens, [:project_id])
    create index(:project_access_tokens, [:user_id])

    create index(:sessions, [:project_id])
    create index(:webhooks, [:project_id])
    create index(:prompt_requests, [:project_id])
    create unique_index(:ai_token_pools, [:project_id])
    create index(:ai_token_contributions, [:project_id])
    create index(:ai_token_earnings, [:project_id])
    create index(:audit_logs, [:project_id])
  end
end
