defmodule MicelioWeb.ActivityPubControllerTest do
  use MicelioWeb.ConnCase, async: true

  alias Micelio.Accounts
  alias Micelio.Fediverse
  alias Micelio.Repositories

  defp create_handle do
    email = "ap#{System.unique_integer()}@example.com"
    {:ok, user} = Accounts.get_or_create_user_by_email(email)
    user.account.handle
  end

  defp create_repository(attrs \\ %{}) do
    suffix = System.unique_integer([:positive])

    {:ok, organization} =
      Accounts.create_organization(%{handle: "org#{suffix}", name: "Org #{suffix}"})

    {:ok, repository} =
      Micelio.Repositories.create_repository(%{
        handle: Map.get(attrs, :handle, "proj#{suffix}"),
        name: Map.get(attrs, :name, "Project #{suffix}"),
        description: Map.get(attrs, :description, "ActivityPub project"),
        organization_id: organization.id,
        visibility: Map.get(attrs, :visibility, "public")
      })

    {organization, repository}
  end

  test "webfinger returns actor link", %{conn: conn} do
    handle = create_handle()
    resource = Fediverse.webfinger_subject(handle)

    conn = get(conn, ~p"/.well-known/webfinger?#{%{resource: resource}}")
    response = json_response(conn, 200)

    assert response["subject"] == resource
    [link] = response["links"]
    assert link["rel"] == "self"
    assert link["type"] == "application/activity+json"
    assert link["href"] == Fediverse.actor_url(handle)
  end

  test "actor returns activitypub payload", %{conn: conn} do
    handle = create_handle()

    conn = get(conn, ~p"/ap/actors/#{handle}")
    response = json_response(conn, 200)

    assert response["id"] == Fediverse.actor_url(handle)
    assert response["preferredUsername"] == handle
    assert response["inbox"] == Fediverse.inbox_url(handle)
    assert response["outbox"] == Fediverse.outbox_url(handle)
    assert response["followers"] == Fediverse.followers_url(handle)
    assert response["following"] == Fediverse.following_url(handle)
    assert "https://www.w3.org/ns/activitystreams" in response["@context"]
  end

  test "profile returns activitypub payload", %{conn: conn} do
    handle = create_handle()

    conn = get(conn, ~p"/ap/profiles/#{handle}")
    response = json_response(conn, 200)

    assert response["id"] == Fediverse.profile_activity_url(handle)
    assert response["type"] == "Profile"
    assert response["name"] == handle
    assert response["url"] == Fediverse.profile_url(handle)
    assert response["describes"] == Fediverse.actor_url(handle)
  end

  test "project returns activitypub payload", %{conn: conn} do
    {organization, repository} = create_repository()
    account_handle = organization.account.handle

    conn = get(conn, ~p"/ap/repositories/#{account_handle}/#{repository.handle}")
    response = json_response(conn, 200)

    assert response["id"] == Fediverse.project_activity_url(account_handle, repository.handle)
    assert response["type"] == "Project"
    assert response["name"] == repository.name
    assert response["summary"] == repository.description
    assert response["url"] == Fediverse.repository_url(account_handle, repository.handle)
    assert response["attributedTo"] == Fediverse.actor_url(account_handle)
  end

  test "outbox is an empty ordered collection", %{conn: conn} do
    handle = create_handle()

    conn = get(conn, ~p"/ap/actors/#{handle}/outbox")
    response = json_response(conn, 200)

    assert response["type"] == "OrderedCollection"
    assert response["totalItems"] == 0
    assert response["orderedItems"] == []
  end

  test "inbox accepts activities", %{conn: conn} do
    handle = create_handle()

    conn =
      conn
      |> put_req_header("content-type", "application/activity+json")
      |> post(~p"/ap/actors/#{handle}/inbox", %{
        "type" => "Follow",
        "actor" => "https://example.com/users/alice"
      })

    assert conn.status == 202
  end

  test "follow activity is stored in followers collection", %{conn: conn} do
    handle = create_handle()
    actor = "https://example.com/users/alice"

    conn =
      conn
      |> put_req_header("content-type", "application/activity+json")
      |> post(~p"/ap/actors/#{handle}/inbox", %{
        "type" => "Follow",
        "actor" => actor
      })

    assert conn.status == 202

    conn = get(conn, ~p"/ap/actors/#{handle}/followers")
    response = json_response(conn, 200)

    assert response["totalItems"] == 1
    assert response["orderedItems"] == [actor]
  end

  test "undo follow removes follower", %{conn: conn} do
    handle = create_handle()
    actor = "https://example.com/users/alice"

    conn =
      conn
      |> put_req_header("content-type", "application/activity+json")
      |> post(~p"/ap/actors/#{handle}/inbox", %{
        "type" => "Follow",
        "actor" => actor
      })

    assert conn.status == 202

    conn = recycle(conn)

    conn =
      conn
      |> put_req_header("content-type", "application/activity+json")
      |> post(~p"/ap/actors/#{handle}/inbox", %{
        "type" => "Undo",
        "actor" => actor,
        "object" => %{"type" => "Follow"}
      })

    assert conn.status == 202

    conn =
      conn
      |> recycle()
      |> get(~p"/ap/actors/#{handle}/followers")

    response = json_response(conn, 200)

    assert response["totalItems"] == 0
    assert response["orderedItems"] == []
  end

  test "unknown actor returns 404", %{conn: conn} do
    conn = get(conn, ~p"/ap/actors/unknown")
    assert conn.status == 404
  end

  test "private project returns 404", %{conn: conn} do
    {organization, repository} = create_repository(%{visibility: "private"})

    conn = get(conn, ~p"/ap/repositories/#{organization.account.handle}/#{repository.handle}")
    assert conn.status == 404
  end
end
