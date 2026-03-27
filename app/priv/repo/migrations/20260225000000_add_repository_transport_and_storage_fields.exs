defmodule Micelio.Repo.Migrations.AddRepositoryTransportAndStorageFields do
  use Ecto.Migration

  def change do
    execute("""
    DO $$
    BEGIN
      IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_schema = 'public'
          AND table_name = 'repositories'
          AND column_name = 'push_protocol'
      ) THEN
        ALTER TABLE repositories
          ADD COLUMN push_protocol varchar(12);
      END IF;
      IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_schema = 'public'
          AND table_name = 'repositories'
          AND column_name = 'push_host'
      ) THEN
        ALTER TABLE repositories
          ADD COLUMN push_host varchar(255);
      END IF;
      IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_schema = 'public'
          AND table_name = 'repositories'
          AND column_name = 'push_namespace'
      ) THEN
        ALTER TABLE repositories
          ADD COLUMN push_namespace varchar(255);
      END IF;
      IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_schema = 'public'
          AND table_name = 'repositories'
          AND column_name = 'push_repository'
      ) THEN
        ALTER TABLE repositories
          ADD COLUMN push_repository varchar(255);
      END IF;
      IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_schema = 'public'
          AND table_name = 'repositories'
          AND column_name = 'storage_backend'
      ) THEN
        ALTER TABLE repositories
          ADD COLUMN storage_backend varchar(20);
      END IF;
      IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_schema = 'public'
          AND table_name = 'repositories'
          AND column_name = 'storage_key_prefix'
      ) THEN
        ALTER TABLE repositories
          ADD COLUMN storage_key_prefix varchar(255);
      END IF;
    END
    $$;
    """)

    execute("""
    CREATE INDEX IF NOT EXISTS repositories_storage_backend_index
      ON repositories (storage_backend);
    """)
  end
end
