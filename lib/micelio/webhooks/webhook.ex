defmodule Micelio.Webhooks.Webhook do
  use Micelio.Schema

  import Ecto.Changeset

  @allowed_events ["push", "session.landed"]

  schema "webhooks" do
    field :url, :string
    field :events, {:array, :string}, default: []
    field :secret, :string
    field :active, :boolean, default: true

    belongs_to :repository, Micelio.Repositories.Repository

    timestamps(type: :utc_datetime)
  end

  @doc """
  Changeset for creating or updating a webhook.
  """
  def changeset(webhook, attrs) do
    webhook
    |> cast(attrs, [:url, :events, :secret, :active, :repository_id])
    |> normalize_events()
    |> validate_required([:url, :events, :repository_id])
    |> validate_length(:events, min: 1)
    |> validate_events()
    |> validate_length(:secret, max: 255)
    |> validate_url()
    |> assoc_constraint(:repository)
  end

  @doc """
  Returns the list of allowed webhook events.
  """
  def allowed_events do
    @allowed_events
  end

  defp normalize_events(changeset) do
    update_change(changeset, :events, fn events ->
      if is_list(events) do
        events
        |> Enum.map(&String.downcase/1)
        |> Enum.uniq()
      else
        events
      end
    end)
  end

  defp validate_events(changeset) do
    validate_change(changeset, :events, fn :events, events ->
      cond do
        not is_list(events) ->
          [events: "must be a list"]

        Enum.any?(events, &(!is_binary(&1) or &1 == "")) ->
          [events: "must contain only non-empty strings"]

        true ->
          invalid = Enum.reject(events, &(&1 in @allowed_events))

          if invalid == [] do
            []
          else
            [events: "contains unsupported events: #{Enum.join(invalid, ", ")}"]
          end
      end
    end)
  end

  defp validate_url(changeset) do
    validate_change(changeset, :url, fn :url, url ->
      case normalize_url(url) do
        {:ok, _} -> []
        :error -> [url: "must be a valid http(s) URL"]
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
