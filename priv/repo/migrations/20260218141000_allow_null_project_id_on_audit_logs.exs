defmodule Micelio.Repo.Migrations.AllowNullProjectIdOnAuditLogs do
  use Ecto.Migration

  def change do
    execute("""
    DO $$
    BEGIN
      IF EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_schema = 'public'
          AND table_name = 'audit_logs'
          AND column_name = 'repository_id'
          AND is_nullable = 'NO'
      ) THEN
        ALTER TABLE audit_logs
          ALTER COLUMN repository_id DROP NOT NULL;
      END IF;
    END
    $$;
    """)
  end
end
