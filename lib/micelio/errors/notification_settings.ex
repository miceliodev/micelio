defmodule Micelio.Errors.NotificationSettings do
  use Ecto.Schema

  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "error_notification_settings" do
    field :email_enabled, :boolean, default: true
    field :webhook_url, :string
    field :slack_webhook_url, :string
    field :notify_on_new, :boolean, default: true
    field :notify_on_threshold, :boolean, default: true
    field :notify_on_critical, :boolean, default: true
    field :quiet_hours_enabled, :boolean, default: false
    field :quiet_hours_start, :integer, default: 0
    field :quiet_hours_end, :integer, default: 0

    timestamps(type: :utc_datetime)
  end

  def changeset(settings, attrs) do
    settings
    |> cast(attrs, [
      :email_enabled,
      :webhook_url,
      :slack_webhook_url,
      :notify_on_new,
      :notify_on_threshold,
      :notify_on_critical,
      :quiet_hours_enabled,
      :quiet_hours_start,
      :quiet_hours_end
    ])
    |> update_change(:webhook_url, &normalize_optional_url/1)
    |> update_change(:slack_webhook_url, &normalize_optional_url/1)
    |> validate_number(:quiet_hours_start, greater_than_or_equal_to: 0, less_than: 24)
    |> validate_number(:quiet_hours_end, greater_than_or_equal_to: 0, less_than: 24)
    |> validate_optional_url(:webhook_url)
    |> validate_optional_url(:slack_webhook_url)
  end

  defp normalize_optional_url(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp normalize_optional_url(value), do: value

  defp validate_optional_url(changeset, field) do
    validate_change(changeset, field, fn ^field, url ->
      if is_binary(url) do
        case normalize_url(url) do
          {:ok, _} -> []
          :error -> [{field, "must be a valid http(s) URL"}]
        end
      else
        []
      end
    end)
  end

  defp normalize_url(url) when is_binary(url) do
    url = String.trim(url)
    uri = URI.parse(url)

    if uri.scheme in ["http", "https"] and is_binary(uri.host) and uri.host != "" do
      {:ok, url}
    else
      :error
    end
  end

  defp normalize_url(_), do: :error
end
