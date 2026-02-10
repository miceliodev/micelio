defmodule Micelio.AdminTest do
  use Micelio.DataCase, async: true

  alias Micelio.Accounts.{Account, User}
  alias Micelio.Admin
  alias Micelio.Repo
  alias Micelio.{Accounts, Projects, Sessions}

  setup do
    Repo.delete_all(Account)
    Repo.delete_all(User)
    :ok
  end

  describe "admin access" do
    test "admin_emails/0 returns configured emails normalized to lowercase" do
      assert Admin.admin_emails() == ["admin@example.com"]
    end

    test "admin_user?/1 matches configured emails case-insensitively" do
      assert Admin.admin_user?(%User{email: "ADMIN@EXAMPLE.COM"})
      refute Admin.admin_user?(%User{email: "member@example.com"})
    end
  end

  describe "admin dashboard queries" do
    test "dashboard_stats/0 returns aggregate counts" do
      {:ok, user1} = Accounts.get_or_create_user_by_email("admin@example.com")
      {:ok, _user2} = Accounts.get_or_create_user_by_email("member@example.com")

      {:ok, organization} =
        Accounts.create_organization_for_user(user1, %{name: "Acme", handle: "acme"})

      {:ok, repository} =
        Micelio.Repositories.create_repository(%{
          name: "Acme Repo",
          handle: "acme-repo",
          organization_id: organization.id,
          visibility: "public"
        })

      {:ok, _private_repository} =
        Micelio.Repositories.create_repository(%{
          name: "Acme Private",
          handle: "acme-private",
          organization_id: organization.id,
          visibility: "private"
        })

      {:ok, _session} =
        Sessions.create_session(%{
          session_id: "session-1",
          goal: "Ship overview",
          repository_id: repository.id,
          user_id: user1.id
        })

      stats = Admin.dashboard_stats()

      assert stats.users == 2
      assert stats.admin_emails_configured == 1
      assert stats.admin_users == 1
      assert stats.organizations == 1
      assert stats.repositories == 2
      assert stats.sessions == 1
      assert stats.public_repositories == 1
      assert stats.private_repositories == 1
    end

    test "list_recent_users/1 returns users in reverse chronological order" do
      {:ok, older} = Accounts.get_or_create_user_by_email("older@example.com")
      {:ok, newer} = Accounts.get_or_create_user_by_email("newer@example.com")

      older = set_inserted_at(older, ~N[2024-01-01 00:00:00])
      newer = set_inserted_at(newer, ~N[2024-01-02 00:00:00])

      recent_users = Admin.list_recent_users(2)

      assert Enum.map(recent_users, & &1.id) == [newer.id, older.id]
      assert Enum.all?(recent_users, fn user -> user.account.handle != "" end)
    end

    test "list_recent_organizations/1 returns organizations in reverse chronological order" do
      {:ok, user} = Accounts.get_or_create_user_by_email("org_admin@example.com")

      {:ok, older_org} =
        Accounts.create_organization_for_user(user, %{name: "Older Org", handle: "older-org"})

      {:ok, newer_org} =
        Accounts.create_organization_for_user(user, %{name: "Newer Org", handle: "newer-org"})

      older_org = set_inserted_at(older_org, ~N[2024-01-01 00:00:00])
      newer_org = set_inserted_at(newer_org, ~N[2024-01-02 00:00:00])

      recent_orgs = Admin.list_recent_organizations(2)

      assert Enum.map(recent_orgs, & &1.id) == [newer_org.id, older_org.id]
      assert Enum.all?(recent_orgs, fn org -> org.account.handle != "" end)
    end

    test "list_recent_repositories/1 returns projects in reverse chronological order" do
      {:ok, user} = Accounts.get_or_create_user_by_email("repository_admin@example.com")

      {:ok, organization} =
        Accounts.create_organization_for_user(user, %{name: "Acme", handle: "acme"})

      {:ok, older_project} =
        Micelio.Repositories.create_repository(%{
          name: "Older Repo",
          handle: "older-repo",
          organization_id: organization.id,
          visibility: "public"
        })

      {:ok, newer_project} =
        Micelio.Repositories.create_repository(%{
          name: "Newer Repo",
          handle: "newer-repo",
          organization_id: organization.id,
          visibility: "public"
        })

      older_repository = set_inserted_at(older_project, ~N[2024-01-01 00:00:00])
      newer_repository = set_inserted_at(newer_project, ~N[2024-01-02 00:00:00])

      recent_repositories = Admin.list_recent_repositories(2)

      assert Enum.map(recent_repositories, & &1.id) == [newer_repository.id, older_repository.id]

      assert Enum.all?(recent_repositories, fn repository ->
               repository.organization.account.handle != ""
             end)
    end

    test "list_recent_sessions/1 preloads related data in reverse order" do
      {:ok, user} = Accounts.get_or_create_user_by_email("user@example.com")

      {:ok, organization} =
        Accounts.create_organization_for_user(user, %{name: "Acme", handle: "acme"})

      {:ok, repository} =
        Micelio.Repositories.create_repository(%{
          name: "Acme Repo",
          handle: "acme-repo",
          organization_id: organization.id,
          visibility: "public"
        })

      {:ok, older_session} =
        Sessions.create_session(%{
          session_id: "session-older",
          goal: "Older",
          repository_id: repository.id,
          user_id: user.id
        })

      {:ok, newer_session} =
        Sessions.create_session(%{
          session_id: "session-newer",
          goal: "Newer",
          repository_id: repository.id,
          user_id: user.id
        })

      older_session = set_inserted_at(older_session, ~N[2024-01-01 00:00:00])
      newer_session = set_inserted_at(newer_session, ~N[2024-01-02 00:00:00])

      recent_sessions = Admin.list_recent_sessions(2)

      assert Enum.map(recent_sessions, & &1.id) == [newer_session.id, older_session.id]

      assert Enum.all?(recent_sessions, fn session ->
               session.user.email != "" and
                 session.repository.organization.account.handle != ""
             end)
    end

    test "usage_dashboard_stats/0 and list_repository_usage/1 return prompt usage totals" do
      {:ok, admin} = Accounts.get_or_create_user_by_email("admin@example.com")

      {:ok, organization} =
        Accounts.create_organization_for_user(admin, %{name: "Acme", handle: "acme"})

      {:ok, repository_one} =
        Micelio.Repositories.create_repository(%{
          name: "Project One",
          handle: "project-one",
          organization_id: organization.id,
          visibility: "public"
        })

      {:ok, repository_two} =
        Micelio.Repositories.create_repository(%{
          name: "Project Two",
          handle: "project-two",
          organization_id: organization.id,
          visibility: "public"
        })

      {:ok, pr_one} =
        create_prompt_request(repository_one, admin, %{token_count: 150})

      {:ok, _pr_two} =
        create_prompt_request(repository_one, admin, %{token_count: 75})

      {:ok, pr_three} =
        create_prompt_request(repository_two, admin, %{token_count: 200})

      {:ok, _} = Micelio.PromptRequests.review_prompt_request(pr_one, admin, :accepted)
      {:ok, _} = Micelio.PromptRequests.review_prompt_request(pr_three, admin, :accepted)

      stats = Admin.usage_dashboard_stats()
      assert stats.tokens_spent == 425
      assert stats.accepted_prompt_requests == 2
      assert stats.total_prompt_requests == 3

      repositories = Admin.list_repository_usage(2)
      assert Enum.map(repositories, & &1.repository_id) == [repository_one.id, repository_two.id]

      [top | rest] = repositories
      assert top.tokens_spent == 225
      assert top.accepted_prompt_requests == 1
      assert top.total_prompt_requests == 2

      assert Enum.any?(rest, fn entry ->
               entry.repository_id == repository_two.id and entry.tokens_spent == 200
             end)
    end
  end

  defp set_inserted_at(struct, inserted_at) do
    inserted_at =
      case {struct.__struct__.__schema__(:type, :inserted_at), inserted_at} do
        {:utc_datetime, %NaiveDateTime{} = naive} -> DateTime.from_naive!(naive, "Etc/UTC")
        {:naive_datetime, %DateTime{} = datetime} -> DateTime.to_naive(datetime)
        {_type, value} -> value
      end

    struct
    |> Ecto.Changeset.change(%{inserted_at: inserted_at, updated_at: inserted_at})
    |> Repo.update!()
  end

  defp create_prompt_request(repository, user, attrs) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    base_attrs = %{
      title: "Ship usage metrics",
      prompt: "Build usage dashboard.",
      result: "Done",
      system_prompt: "System",
      conversation: %{"messages" => [%{"role" => "user", "content" => "hi"}]},
      origin: :ai_generated,
      model: "gpt-4",
      model_version: "2024-01-01",
      token_count: 120,
      generated_at: now
    }

    Micelio.PromptRequests.create_prompt_request(Map.merge(base_attrs, attrs),
      project: repository,
      user: user
    )
  end
end
