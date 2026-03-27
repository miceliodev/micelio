defmodule MicelioWeb.Browser.ProfileControllerTest do
  use MicelioWeb.ConnCase, async: true

  alias Micelio.Accounts
  alias Micelio.Sessions
  alias Micelio.Storage

  defmodule SuccessValidator do
    def validate(_config), do: {:ok, %{ok?: true, errors: []}}
  end

  setup :register_and_log_in_user
  setup :assign_success_validator

  defp assign_success_validator(%{conn: conn}) do
    %{conn: assign(conn, :s3_validator, SuccessValidator)}
  end

  test "shows profile page with devices link", %{conn: conn, user: user} do
    conn = get(conn, ~p"/account")
    html = html_response(conn, 200)

    assert html =~ "@#{user.account.handle}"
    assert html =~ "id=\"account-devices-link\""
  end

  test "shows navbar user link on authenticated pages", %{conn: conn, user: _user} do
    conn = get(conn, ~p"/account/devices")
    html = html_response(conn, 200)

    assert html =~ "class=\"navbar-user-avatar\""
    assert html =~ "id=\"navbar-user\""
    assert html =~ "href=\"/account\""
    assert html =~ "gravatar.com/avatar/"
  end

  test "shows owned repositories list for admin organizations", %{conn: conn, user: user} do
    {:ok, organization} =
      Accounts.create_organization_for_user(user, %{
        handle: "owned-org",
        name: "Owned Org"
      })

    {:ok, repository} =
      Micelio.Repositories.create_repository(%{
        handle: "owned-project",
        name: "Owned Project",
        organization_id: organization.id,
        visibility: "private"
      })

    conn = get(conn, ~p"/account")
    html = html_response(conn, 200)

    assert html =~ "Repositories"
    assert html =~ "owned-project-#{repository.id}"
    assert html =~ "#{organization.account.handle}/#{repository.handle}"
  end

  test "shows organizations list for memberships", %{conn: conn, user: user} do
    {:ok, organization} =
      Accounts.create_organization_for_user(user, %{
        handle: "team-org",
        name: "Team Org"
      })

    {:ok, other_user} = Accounts.get_or_create_user_by_email("member@example.com")

    assert {:ok, _membership} =
             Accounts.create_organization_membership(%{
               user_id: other_user.id,
               organization_id: organization.id,
               role: "member"
             })

    conn = get(conn, ~p"/account")
    html = html_response(conn, 200)

    assert html =~ "Organizations"
    assert html =~ "organization-#{organization.id}"
    assert html =~ organization.name
    assert html =~ "@#{organization.account.handle}"
  end

  test "shows activity graph for landed sessions", %{conn: conn, user: user} do
    {:ok, organization} =
      Accounts.create_organization_for_user(user, %{
        handle: "activity-org",
        name: "Activity Org"
      })

    {:ok, repository} =
      Micelio.Repositories.create_repository(%{
        handle: "activity-project",
        name: "Activity Project",
        organization_id: organization.id,
        visibility: "private"
      })

    {:ok, session} =
      Sessions.create_session(%{
        session_id: "activity-session",
        goal: "Ship activity",
        repository_id: repository.id,
        user_id: user.id
      })

    {:ok, _} = Sessions.land_session(session)

    conn = get(conn, ~p"/account")
    html = html_response(conn, 200)

    assert html =~ "id=\"account-activity\""
    assert html =~ "class=\"account-section-title\">Activity"
    assert html =~ "activity-graph"
    assert html =~ "aria-label=\"1 contributions\""
    assert html =~ "activity-graph-legend"
  end

  test "shows storage section with S3 form", %{conn: conn} do
    conn = get(conn, ~p"/account")
    html = html_response(conn, 200)

    assert html =~ "id=\"account-storage\""
    assert html =~ "id=\"account-storage-settings\""
  end

  test "saves S3 configuration", %{conn: conn, user: user} do
    params = %{
      "provider" => "aws_s3",
      "bucket_name" => "user-bucket",
      "region" => "us-east-1",
      "endpoint_url" => "",
      "access_key_id" => "access-key",
      "secret_access_key" => "secret-key",
      "path_prefix" => "sessions/"
    }

    conn = patch(conn, ~p"/account/storage/s3", %{"s3_config" => params})

    assert redirected_to(conn) == ~p"/settings/storage"
    assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "S3 configuration saved"

    config = Storage.get_user_s3_config(user)
    assert config.bucket_name == "user-bucket"
    assert config.provider == :aws_s3
    assert config.validated_at
  end
end
