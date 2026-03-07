defmodule Micelio.Repo.Migrations.CreateS3Configs do
  use Ecto.Migration

  def change do
    execute("""
    CREATE TABLE IF NOT EXISTS s3_configs (
      id uuid NOT NULL,
      user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
      provider text NOT NULL,
      bucket_name text NOT NULL,
      region text,
      endpoint_url text,
      access_key_id bytea NOT NULL,
      secret_access_key bytea NOT NULL,
      path_prefix text,
      validated_at timestamp(0),
      last_error text,
      inserted_at timestamp(0) NOT NULL,
      updated_at timestamp(0) NOT NULL,
      CONSTRAINT s3_configs_pkey PRIMARY KEY (id)
    );
    """)

    execute("""
    CREATE UNIQUE INDEX IF NOT EXISTS s3_configs_user_id_index
      ON s3_configs (user_id);
    """)
  end
end
