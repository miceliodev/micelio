defmodule Micelio.Errors do
  @moduledoc """
  Persistence helpers for error tracking.
  """

  import Ecto.Query, warn: false

  alias Micelio.Errors.Config
  alias Micelio.Errors.Error
  alias Micelio.Errors.NotificationSettings
  alias Micelio.Errors.RetentionSettings
  alias Micelio.Repo

  @default_limit 20
  @default_sort :newest
  @sorts [:newest, :oldest, :occurrences]

  def create_error(attrs) when is_map(attrs) do
    %Error{}
    |> Error.changeset(attrs)
    |> Repo.insert()
  end

  def change_error(%Error{} = error, attrs \\ %{}) do
    Error.changeset(error, attrs)
  end

  def list_errors(opts \\ []) do
    filters = Keyword.get(opts, :filters, %{})
    sort = normalize_sort(Keyword.get(opts, :sort, @default_sort))
    page = normalize_page(Keyword.get(opts, :page, 1))
    limit = Keyword.get(opts, :limit, @default_limit)

    query =
      Error
      |> apply_filters(filters)
      |> apply_sort(sort)

    total = Repo.aggregate(query, :count, :id)

    errors =
      query
      |> limit(^limit)
      |> offset(^(limit * (page - 1)))
      |> Repo.all()

    %{
      errors: errors,
      total: total,
      page: page,
      limit: limit,
      sort: sort
    }
  end

  def get_error!(id), do: Repo.get!(Error, id)

  def get_notification_settings do
    Repo.one(NotificationSettings) || %NotificationSettings{}
  end

  def get_retention_settings do
    Repo.one(RetentionSettings) ||
      %RetentionSettings{
        resolved_retention_days: Config.resolved_retention_days(),
        unresolved_retention_days: Config.unresolved_retention_days(),
        archive_enabled: Config.retention_archive_enabled?()
      }
  end

  def change_retention_settings(%RetentionSettings{} = settings, attrs \\ %{}) do
    RetentionSettings.changeset(settings, attrs)
  end

  def update_retention_settings(attrs) when is_map(attrs) do
    settings = get_retention_settings()
    changeset = change_retention_settings(settings, attrs)

    if settings.id do
      Repo.update(changeset)
    else
      Repo.insert(changeset)
    end
  end

  def retention_policy do
    settings = get_retention_settings()

    from_settings? = not is_nil(settings.id)

    %{
      resolved_retention_days:
        if(from_settings?,
          do: settings.resolved_retention_days,
          else: Config.resolved_retention_days()
        ),
      unresolved_retention_days:
        if(from_settings?,
          do: settings.unresolved_retention_days,
          else: Config.unresolved_retention_days()
        ),
      archive_enabled:
        if(from_settings?,
          do: settings.archive_enabled,
          else: Config.retention_archive_enabled?()
        ),
      archive_prefix: Config.retention_archive_prefix(),
      table_warn_threshold: Config.retention_table_warn_threshold()
    }
  end

  def change_notification_settings(%NotificationSettings{} = settings, attrs \\ %{}) do
    NotificationSettings.changeset(settings, attrs)
  end

  def update_notification_settings(attrs) when is_map(attrs) do
    settings = get_notification_settings()
    changeset = change_notification_settings(settings, attrs)

    if settings.id do
      Repo.update(changeset)
    else
      Repo.insert(changeset)
    end
  end

  def resolve_error(%Error{} = error, resolved_by_id, note \\ nil) do
    updates =
      %{
        resolved_at: DateTime.utc_now() |> DateTime.truncate(:second),
        resolved_by_id: resolved_by_id
      }
      |> maybe_put_resolution_note(error, note)

    error
    |> Error.changeset(updates)
    |> Repo.update()
  end

  def resolve_similar_errors(%Error{} = error, resolved_by_id, note \\ nil) do
    query =
      from(error in Error,
        where: error.fingerprint == ^error.fingerprint and is_nil(error.resolved_at)
      )

    Repo.transaction(fn ->
      errors = Repo.all(query)

      results =
        Enum.map(errors, fn item ->
          resolve_error(item, resolved_by_id, note)
        end)

      {Enum.count(results), results}
    end)
  end

  def delete_error(%Error{} = error), do: Repo.delete(error)

  def error_overview do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    %{
      last_24h: counts_by_severity(DateTime.add(now, -86_400, :second)),
      last_7d: counts_by_severity(DateTime.add(now, -7 * 86_400, :second)),
      last_30d: counts_by_severity(DateTime.add(now, -30 * 86_400, :second))
    }
  end

  def daily_counts(days \\ 7) when is_integer(days) and days > 0 do
    today = Date.utc_today()
    start_date = Date.add(today, -(days - 1))
    {:ok, start_dt} = DateTime.new(start_date, ~T[00:00:00], "Etc/UTC")
    {:ok, end_dt} = DateTime.new(today, ~T[23:59:59], "Etc/UTC")

    raw =
      Error
      |> where([error], error.occurred_at >= ^start_dt and error.occurred_at <= ^end_dt)
      |> group_by([error], fragment("date_trunc('day', ?)", error.occurred_at))
      |> select([error], {fragment("date_trunc('day', ?)", error.occurred_at), count(error.id)})
      |> Repo.all()
      |> Map.new(fn {date, count} ->
        {NaiveDateTime.to_date(date), count}
      end)

    Enum.map(0..(days - 1), fn offset ->
      date = Date.add(start_date, offset)
      %{date: date, count: Map.get(raw, date, 0)}
    end)
  end

  def delete_expired_errors(opts \\ []) do
    retention_days = Keyword.get(opts, :retention_days, Config.retention_days())

    if is_integer(retention_days) and retention_days > 0 do
      cutoff = DateTime.add(DateTime.utc_now(), -retention_days * 86_400, :second)

      Error
      |> where([error], error.last_seen_at < ^cutoff)
      |> Repo.delete_all()
    else
      {0, nil}
    end
  end

  def sorts, do: @sorts

  defp counts_by_severity(%DateTime{} = cutoff) do
    results =
      Error
      |> where([error], error.occurred_at >= ^cutoff)
      |> group_by([error], error.severity)
      |> select([error], {error.severity, count(error.id)})
      |> Repo.all()
      |> Map.new()

    Error.severities()
    |> Map.new(&{&1, Map.get(results, &1, 0)})
  end

  defp apply_filters(query, filters) do
    query
    |> filter_kind(Map.get(filters, "kind"))
    |> filter_severity(Map.get(filters, "severity"))
    |> filter_status(Map.get(filters, "status"))
    |> filter_query(Map.get(filters, "query"))
    |> filter_user(Map.get(filters, "user_id"))
    |> filter_repository(Map.get(filters, "repository_id"))
    |> filter_date_range(Map.get(filters, "start_date"), Map.get(filters, "end_date"))
  end

  defp filter_kind(query, value) do
    case normalize_enum(value, Error.kinds()) do
      nil -> query
      kind -> where(query, [error], error.kind == ^kind)
    end
  end

  defp filter_severity(query, value) do
    case normalize_enum(value, Error.severities()) do
      nil -> query
      severity -> where(query, [error], error.severity == ^severity)
    end
  end

  defp filter_status(query, "resolved"), do: where(query, [error], not is_nil(error.resolved_at))
  defp filter_status(query, "unresolved"), do: where(query, [error], is_nil(error.resolved_at))
  defp filter_status(query, _), do: query

  defp filter_query(query, value) when is_binary(value) and value != "" do
    where(query, [error], ilike(error.message, ^"%#{value}%"))
  end

  defp filter_query(query, _), do: query

  defp filter_user(query, value) when is_binary(value) and value != "" do
    case Ecto.UUID.cast(value) do
      {:ok, uuid} -> where(query, [error], error.user_id == ^uuid)
      :error -> query
    end
  end

  defp filter_user(query, _), do: query

  defp filter_repository(query, value) when is_binary(value) and value != "" do
    case Ecto.UUID.cast(value) do
      {:ok, uuid} -> where(query, [error], error.repository_id == ^uuid)
      :error -> query
    end
  end

  defp filter_repository(query, _), do: query

  defp filter_date_range(query, start_value, end_value) do
    query
    |> filter_start_date(start_value)
    |> filter_end_date(end_value)
  end

  defp filter_start_date(query, value) when is_binary(value) and value != "" do
    case Date.from_iso8601(value) do
      {:ok, date} ->
        {:ok, start_dt} = DateTime.new(date, ~T[00:00:00], "Etc/UTC")
        where(query, [error], error.occurred_at >= ^start_dt)

      _ ->
        query
    end
  end

  defp filter_start_date(query, _), do: query

  defp filter_end_date(query, value) when is_binary(value) and value != "" do
    case Date.from_iso8601(value) do
      {:ok, date} ->
        {:ok, end_dt} = DateTime.new(date, ~T[23:59:59], "Etc/UTC")
        where(query, [error], error.occurred_at <= ^end_dt)

      _ ->
        query
    end
  end

  defp filter_end_date(query, _), do: query

  defp apply_sort(query, :oldest), do: order_by(query, asc: :last_seen_at)

  defp apply_sort(query, :occurrences),
    do: order_by(query, [error], desc: error.occurrence_count, desc: error.last_seen_at)

  defp apply_sort(query, _), do: order_by(query, desc: :last_seen_at)

  defp normalize_enum(value, allowed) when is_atom(value) do
    if value in allowed, do: value
  end

  defp normalize_enum(value, allowed) when is_binary(value) do
    normalized =
      value
      |> String.trim()
      |> String.downcase()

    if normalized != "" do
      atom = String.to_existing_atom(normalized)

      if atom in allowed, do: atom
    end
  rescue
    ArgumentError -> nil
  end

  defp normalize_enum(_, _), do: nil

  defp normalize_sort(value) when value in @sorts, do: value

  defp normalize_sort(value) when is_binary(value) do
    normalized =
      value
      |> String.trim()
      |> String.downcase()

    case normalized do
      "oldest" -> :oldest
      "occurrences" -> :occurrences
      _ -> @default_sort
    end
  end

  defp normalize_sort(_), do: @default_sort

  defp normalize_page(page) when is_integer(page) and page > 0, do: page

  defp normalize_page(page) when is_binary(page) do
    case Integer.parse(page) do
      {value, _} when value > 0 -> value
      _ -> 1
    end
  end

  defp normalize_page(_), do: 1

  defp maybe_put_resolution_note(updates, %Error{} = error, note)
       when is_binary(note) and note != "" do
    metadata =
      error.metadata
      |> Map.new()
      |> Map.put("resolution_note", note)

    Map.put(updates, :metadata, metadata)
  end

  defp maybe_put_resolution_note(updates, _error, _note), do: updates
end
