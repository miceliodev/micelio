defmodule Micelio.Repo.Migrations.AddForgeFieldsToRepositories do
  use Ecto.Migration

  def change do
    execute("""
    DO $$
    BEGIN
      IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_schema = 'public'
          AND table_name = 'repositories'
          AND column_name = 'forge_provider'
      ) THEN
        ALTER TABLE repositories
          ADD COLUMN forge_provider varchar(20);
      END IF;
      IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_schema = 'public'
          AND table_name = 'repositories'
          AND column_name = 'forge_host'
      ) THEN
        ALTER TABLE repositories
          ADD COLUMN forge_host varchar(120);
      END IF;
      IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_schema = 'public'
          AND table_name = 'repositories'
          AND column_name = 'forge_owner'
      ) THEN
        ALTER TABLE repositories
          ADD COLUMN forge_owner varchar(255);
      END IF;
      IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_schema = 'public'
          AND table_name = 'repositories'
          AND column_name = 'forge_repo'
      ) THEN
        ALTER TABLE repositories
          ADD COLUMN forge_repo varchar(255);
      END IF;
      IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_schema = 'public'
          AND table_name = 'repositories'
          AND column_name = 'forge_external_id'
      ) THEN
        ALTER TABLE repositories
          ADD COLUMN forge_external_id varchar(255);
      END IF;
      IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_schema = 'public'
          AND table_name = 'repositories'
          AND column_name = 'forge_default_branch'
      ) THEN
        ALTER TABLE repositories
          ADD COLUMN forge_default_branch varchar(255);
      END IF;
      IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_schema = 'public'
          AND table_name = 'repositories'
          AND column_name = 'mirror_status'
      ) THEN
        ALTER TABLE repositories
          ADD COLUMN mirror_status varchar(20) DEFAULT 'pending';
      END IF;
      IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_schema = 'public'
          AND table_name = 'repositories'
          AND column_name = 'mirror_last_synced_at'
      ) THEN
        ALTER TABLE repositories
          ADD COLUMN mirror_last_synced_at timestamp;
      END IF;
    END
    $$;
    """)

    execute("""
    CREATE INDEX IF NOT EXISTS repositories_forge_provider_index
      ON repositories (forge_provider);
    """)

    execute("""
    CREATE INDEX IF NOT EXISTS repositories_forge_host_index
      ON repositories (forge_host);
    """)

    execute("""
    CREATE INDEX IF NOT EXISTS repositories_mirror_status_index
      ON repositories (mirror_status);
    """)

    execute("""
    CREATE UNIQUE INDEX IF NOT EXISTS repositories_forge_host_owner_repo_index
      ON repositories (forge_host, lower(forge_owner), lower(forge_repo))
      WHERE forge_host IS NOT NULL AND forge_owner IS NOT NULL AND forge_repo IS NOT NULL;
    """)
  end
end
