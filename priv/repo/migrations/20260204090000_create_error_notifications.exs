defmodule Micelio.Repo.Migrations.CreateErrorNotifications do
  use Ecto.Migration

  def change do
    create table(:error_notification_settings, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :email_enabled, :boolean, default: true, null: false
      add :webhook_url, :string
      add :slack_webhook_url, :string
      add :notify_on_new, :boolean, default: true, null: false
      add :notify_on_threshold, :boolean, default: true, null: false
      add :notify_on_critical, :boolean, default: true, null: false
      add :quiet_hours_enabled, :boolean, default: false, null: false
      add :quiet_hours_start, :integer, default: 0, null: false
      add :quiet_hours_end, :integer, default: 0, null: false

      timestamps(type: :utc_datetime)
    end

    create table(:error_notifications, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :error_id, references(:errors, type: :binary_id, on_delete: :nilify_all)
      add :fingerprint, :string, null: false
      add :severity, :string, null: false
      add :reason, :string, null: false
      add :channels, {:array, :string}, default: [], null: false

      timestamps(type: :utc_datetime)
    end

    create index(:error_notifications, [:fingerprint])
    create index(:error_notifications, [:inserted_at])
    create index(:error_notifications, [:severity])
    create index(:error_notifications, [:reason])
  end
end
