defmodule Micelio.Notifications do
  @moduledoc """
  Email notifications for repository activity.
  """

  alias Micelio.Accounts
  alias Micelio.Mailer
  alias Micelio.Notifications.ActivityEmail
  alias Micelio.Repo
  alias Micelio.Repositories.Repository
  alias Micelio.Sessions.Session

  require Logger

  @supervisor Micelio.Notifications.Supervisor

  @doc """
  Dispatches session landed notifications for a repository.
  """
  def dispatch_session_landed(%Repository{} = repository, %Session{} = session, opts \\ []) do
    async = Keyword.get(opts, :async, default_async?())

    if async do
      case Task.Supervisor.start_child(@supervisor, fn ->
             deliver_session_landed(repository, session)
           end) do
        {:ok, _pid} ->
          :ok

        {:error, reason} ->
          Logger.warning("notification dispatch failed: #{inspect(reason)}")
          :error
      end
    else
      deliver_session_landed(repository, session)
    end
  end

  @doc """
  Delivers session landed emails to organization members.
  """
  def deliver_session_landed(%Repository{} = repository, %Session{} = session) do
    repository = Repo.preload(repository, organization: :account)
    session = Repo.preload(session, :user)

    recipients =
      repository.organization_id
      |> Accounts.list_users_for_organization()
      |> Enum.filter(&valid_recipient?/1)

    emails =
      Enum.map(recipients, fn recipient ->
        ActivityEmail.session_landed_email(recipient, repository, session)
      end)

    case emails do
      [] ->
        :ok

      _ ->
        case Mailer.deliver_many(emails) do
          {:ok, _} -> :ok
          {:error, reason} -> {:error, reason}
        end
    end
  end

  defp valid_recipient?(user) do
    is_binary(user.email) and user.email != ""
  end

  defp default_async? do
    Application.get_env(:micelio, :notifications_async, true)
  end
end
