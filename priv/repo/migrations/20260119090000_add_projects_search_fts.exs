defmodule Micelio.Repo.Migrations.AddProjectsSearchFts do
  use Ecto.Migration

  def up do
    # Add a tsvector column for full-text search
    execute("""
    ALTER TABLE projects
    ADD COLUMN search_vector tsvector
    GENERATED ALWAYS AS (
      setweight(to_tsvector('english', coalesce(name, '')), 'A') ||
      setweight(to_tsvector('english', coalesce(description, '')), 'B')
    ) STORED;
    """)

    # Create a GIN index for fast full-text search
    execute("""
    CREATE INDEX projects_search_idx ON projects USING GIN (search_vector);
    """)
  end

  def down do
    execute("DROP INDEX IF EXISTS projects_search_idx;")
    execute("ALTER TABLE projects DROP COLUMN IF EXISTS search_vector;")
  end
end
