defmodule Micelio.Repo.Migrations.CreateS3Configs do
  use Ecto.Migration

  def change do
    create table(:s3_configs, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :provider, :string, null: false
      add :bucket_name, :string, null: false
      add :region, :string
      add :endpoint_url, :string
      add :access_key_id, :binary, null: false
      add :secret_access_key, :binary, null: false
      add :path_prefix, :string
      add :validated_at, :utc_datetime
      add :last_error, :text

      timestamps(type: :utc_datetime)
    end

    create unique_index(:s3_configs, [:user_id])
  end
end
