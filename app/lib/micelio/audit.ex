defmodule Micelio.Audit do
  @moduledoc """
  Audit logging for repository operations.
  """

  import Ecto.Query

  alias Micelio.Accounts.User
  alias Micelio.AuditLog
  alias Micelio.Repo
  alias Micelio.Repositories.Repository

  def log_repository_action(%Repository{} = repository, action, opts \\ [])
      when is_binary(action) do
    user = Keyword.get(opts, :user)
    metadata = Keyword.get(opts, :metadata, %{})

    attrs =
      %{
        repository_id: repository.id,
        action: action,
        metadata: metadata
      }
      |> maybe_put_user_id(user)

    %AuditLog{}
    |> AuditLog.repository_changeset(attrs)
    |> Repo.insert()
  end

  def log_user_action(%User{} = user, action, opts \\ []) when is_binary(action) do
    metadata = Keyword.get(opts, :metadata, %{})

    attrs = %{
      user_id: user.id,
      action: action,
      metadata: metadata
    }

    %AuditLog{}
    |> AuditLog.user_changeset(attrs)
    |> Repo.insert()
  end

  def list_project_logs(repository_id, opts \\ []) do
    limit = Keyword.get(opts, :limit, 50)

    AuditLog
    |> where([log], log.repository_id == ^repository_id)
    |> order_by([log], desc: log.inserted_at)
    |> limit(^limit)
    |> Repo.all()
  end

  defp maybe_put_user_id(attrs, %User{} = user), do: Map.put(attrs, :user_id, user.id)
  defp maybe_put_user_id(attrs, _), do: attrs
end
