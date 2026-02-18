defmodule Micelio.Activity do
  @moduledoc """
  Aggregates recent activity for user profiles.
  """

  import Ecto.Query

  alias Micelio.Accounts
  alias Micelio.Accounts.User
  alias Micelio.Plans.Plan
  alias Micelio.Repo
  alias Micelio.Sessions.Session

  @doc """
  Returns recent public activity for a user.

  Includes landed sessions, repository stars, and public projects created in admin orgs.
  """
  @spec list_user_activity_public(User.t(), [binary()] | nil, Keyword.t()) :: %{
          items: list(map()),
          has_more?: boolean()
        }
  def list_user_activity_public(%User{} = user, organization_ids \\ nil, opts \\ []) do
    limit = Keyword.get(opts, :limit, 20)

    before =
      opts
      |> Keyword.get(:before, default_before())
      |> DateTime.truncate(:second)

    per_type_limit = limit + 1

    organization_ids =
      case organization_ids do
        nil ->
          user
          |> Accounts.list_organizations_for_user_with_role(:admin)
          |> Enum.map(& &1.id)

        ids ->
          ids
      end

    items =
      list_session_activity(user, before, per_type_limit) ++
        list_plan_activity(user, before, per_type_limit) ++
        list_star_activity(user, before, per_type_limit) ++
        list_repository_activity(organization_ids, before, per_type_limit)

    sorted_items = Enum.sort_by(items, &DateTime.to_unix(&1.occurred_at), :desc)

    %{
      items: Enum.take(sorted_items, limit),
      has_more?: length(sorted_items) > limit
    }
  end

  defp list_session_activity(%User{} = user, before, limit) do
    Session
    |> join(:inner, [s], p in assoc(s, :repository))
    |> join(:left, [s, p], o in assoc(p, :organization))
    |> join(:left, [s, p, o], a in assoc(o, :account))
    |> where([s, _p], s.user_id == ^user.id)
    |> where([s, _p], s.status == "landed")
    |> where([s, _p], not is_nil(s.landed_at))
    |> where([s, _p], s.landed_at < ^before)
    |> where([_s, p], p.visibility == "public")
    |> preload([_s, p, o, a], repository: {p, organization: {o, account: a}})
    |> order_by([s], desc: s.landed_at)
    |> limit(^limit)
    |> Repo.all()
    |> Enum.map(fn session ->
      %{
        id: session.id,
        type: :session_landed,
        project: session.repository,
        occurred_at: session.landed_at
      }
    end)
  end

  defp list_star_activity(%User{} = user, before, limit) do
    ProjectStar
    |> join(:inner, [ps], p in assoc(ps, :repository))
    |> join(:left, [ps, p], o in assoc(p, :organization))
    |> join(:left, [ps, p, o], a in assoc(o, :account))
    |> where([ps, _p], ps.user_id == ^user.id)
    |> where([ps, _p], ps.inserted_at < ^before)
    |> where([_ps, p], p.visibility == "public")
    |> preload([_ps, p, o, a], repository: {p, organization: {o, account: a}})
    |> order_by([ps], desc: ps.inserted_at)
    |> limit(^limit)
    |> Repo.all()
    |> Enum.map(fn star ->
      %{
        id: star.id,
        type: :repository_starred,
        project: star.repository,
        occurred_at: star.inserted_at
      }
    end)
  end

  defp list_plan_activity(%User{} = user, before, limit) do
    Plan
    |> join(:inner, [pr], p in assoc(pr, :repository))
    |> join(:left, [pr, p], o in assoc(p, :organization))
    |> join(:left, [pr, p, o], a in assoc(o, :account))
    |> where([pr, _p], pr.user_id == ^user.id)
    |> where([pr, _p], pr.inserted_at < ^before)
    |> where([_pr, p], p.visibility == "public")
    |> preload([_pr, p, o, a], repository: {p, organization: {o, account: a}})
    |> order_by([pr], desc: pr.inserted_at)
    |> limit(^limit)
    |> Repo.all()
    |> Enum.map(fn plan ->
      %{
        id: plan.id,
        type: :plan_submitted,
        project: plan.repository,
        origin: plan.origin,
        occurred_at: plan.inserted_at
      }
    end)
  end

  defp list_repository_activity([], _before, _limit), do: []

  defp list_repository_activity(organization_ids, before, limit) do
    Project
    |> join(:left, [p], o in assoc(p, :organization))
    |> join(:left, [p, o], a in assoc(o, :account))
    |> where([p], p.organization_id in ^organization_ids)
    |> where([p], p.visibility == "public")
    |> where([p], p.inserted_at < ^before)
    |> preload([_p, o, a], organization: {o, account: a})
    |> order_by([p], desc: p.inserted_at)
    |> limit(^limit)
    |> Repo.all()
    |> Enum.map(fn repository ->
      %{
        id: repository.id,
        type: :repository_created,
        project: repository,
        occurred_at: repository.inserted_at
      }
    end)
  end

  defp default_before do
    DateTime.utc_now()
    |> DateTime.add(1, :second)
  end
end
