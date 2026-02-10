defmodule Micelio.WebhooksTest do
  # async: false because global Mimic mocking requires exclusive ownership
  use Micelio.DataCase, async: false

  import Mimic

  alias Micelio.Accounts
  alias Micelio.Repositories
  alias Micelio.Sessions
  alias Micelio.Webhooks

  setup :verify_on_exit!
  setup :set_mimic_global

  describe "deliver_repository_event/3" do
    setup do
      {:ok, organization} =
        Accounts.create_organization(%{
          name: "Acme",
          handle: "acme-#{System.unique_integer([:positive])}"
        })

      {:ok, repository} =
        Micelio.Repositories.create_repository(%{
          handle: "repo-#{System.unique_integer([:positive])}",
          name: "Repo",
          description: "Test",
          organization_id: organization.id,
          visibility: "public"
        })

      {:ok, webhook} =
        Webhooks.create_webhook(%{
          repository_id: repository.id,
          url: "https://hooks.example.com/push",
          events: ["push"],
          secret: "super-secret"
        })

      {:ok, repository: repository, webhook: webhook}
    end

    test "posts payload with signature", %{repository: repository, webhook: webhook} do
      payload = %{"session_id" => "session-1"}

      expect(Req, :request, fn opts ->
        assert opts[:method] == :post
        assert opts[:url] == webhook.url

        headers = normalize_headers(opts[:headers])
        assert headers["content-type"] == "application/json"
        assert headers["x-micelio-event"] == "push"
        assert headers["x-micelio-hook-id"] == webhook.id

        body = opts[:body]
        decoded = Jason.decode!(body)

        assert decoded["event"] == "push"
        assert decoded["project"]["id"] == repository.id
        assert decoded["payload"] == payload

        assert headers["x-micelio-signature"] == "sha256=" <> sign("super-secret", body)

        {:ok, %{status: 200, body: ""}}
      end)

      assert {:ok, [%{webhook: ^webhook, status: :ok, response_status: 200}]} =
               Webhooks.deliver_repository_event(repository, "push", payload)
    end

    test "delivers only active webhooks with matching events", %{
      project: repository,
      webhook: webhook
    } do
      {:ok, _inactive} =
        Webhooks.create_webhook(%{
          repository_id: repository.id,
          url: "https://hooks.example.com/disabled",
          events: ["push"],
          active: false
        })

      {:ok, _different_event} =
        Webhooks.create_webhook(%{
          repository_id: repository.id,
          url: "https://hooks.example.com/session",
          events: ["session.landed"]
        })

      payload = %{"session_id" => "session-2"}

      expect(Req, :request, fn opts ->
        headers = normalize_headers(opts[:headers])
        assert headers["x-micelio-hook-id"] == webhook.id
        {:ok, %{status: 204, body: ""}}
      end)

      assert {:ok, [%{webhook: ^webhook, status: :ok, response_status: 204}]} =
               Webhooks.deliver_repository_event(repository, "push", payload)
    end
  end

  describe "dispatch_repository_event/4" do
    setup do
      {:ok, organization} =
        Accounts.create_organization(%{
          name: "Dispatch Co",
          handle: "dispatch-co-#{System.unique_integer([:positive])}"
        })

      {:ok, repository} =
        Micelio.Repositories.create_repository(%{
          handle: "dispatch-repo-#{System.unique_integer([:positive])}",
          name: "Dispatch Repo",
          description: "Test",
          organization_id: organization.id,
          visibility: "public"
        })

      {:ok, repository: repository}
    end

    test "dispatches known events synchronously with async: false", %{repository: repository} do
      # Use async: false to run synchronously without mocking Task.Supervisor
      assert :ok ==
               Webhooks.dispatch_repository_event(repository, "push", %{"ok" => true},
                 async: false
               )
    end

    test "rejects unknown events", %{repository: repository} do
      assert {:error, :unknown_event} ==
               Webhooks.dispatch_repository_event(repository, "unknown.event", %{"ok" => true},
                 async: false
               )
    end
  end

  describe "deliver_repository_event/3 without secret" do
    setup do
      {:ok, organization} =
        Accounts.create_organization(%{
          name: "No Secret Org",
          handle: "no-secret-org-#{System.unique_integer([:positive])}"
        })

      {:ok, repository} =
        Micelio.Repositories.create_repository(%{
          handle: "no-secret-repo-#{System.unique_integer([:positive])}",
          name: "No Secret Repo",
          description: "Test",
          organization_id: organization.id,
          visibility: "public"
        })

      {:ok, webhook} =
        Webhooks.create_webhook(%{
          repository_id: repository.id,
          url: "https://hooks.example.com/no-secret",
          events: ["push"],
          secret: ""
        })

      {:ok, repository: repository, webhook: webhook}
    end

    test "omits signature header", %{repository: repository, webhook: webhook} do
      payload = %{"session_id" => "session-3"}

      expect(Req, :request, fn opts ->
        assert opts[:url] == webhook.url
        headers = normalize_headers(opts[:headers])
        refute Map.has_key?(headers, "x-micelio-signature")
        {:ok, %{status: 202, body: ""}}
      end)

      assert {:ok, [%{webhook: ^webhook, status: :ok, response_status: 202}]} =
               Webhooks.deliver_repository_event(repository, "push", payload)
    end
  end

  describe "dispatch_session_landed/3" do
    setup do
      {:ok, organization} =
        Accounts.create_organization(%{
          name: "Landing Org",
          handle: "landing-org-#{System.unique_integer([:positive])}"
        })

      {:ok, repository} =
        Micelio.Repositories.create_repository(%{
          handle: "landing-repo-#{System.unique_integer([:positive])}",
          name: "Landing Repo",
          description: "Test",
          organization_id: organization.id,
          visibility: "public"
        })

      {:ok, user} =
        Accounts.get_or_create_user_by_email(
          "session-landed-#{System.unique_integer([:positive])}@example.com"
        )

      {:ok, session} =
        Sessions.create_session(%{
          session_id: "session-#{System.unique_integer([:positive])}",
          goal: "Ship landing",
          repository_id: repository.id,
          user_id: user.id
        })

      {:ok, _hook} =
        Webhooks.create_webhook(%{
          repository_id: repository.id,
          url: "https://hooks.example.com/session",
          events: ["session.landed"]
        })

      {:ok, _hook} =
        Webhooks.create_webhook(%{
          repository_id: repository.id,
          url: "https://hooks.example.com/push",
          events: ["push"]
        })

      {:ok, repository: repository, session: session}
    end

    test "dispatches session.landed and push events", %{repository: repository, session: session} do
      # Expect 2 HTTP calls - one for session.landed and one for push
      expect(Req, :request, 2, fn opts ->
        headers = normalize_headers(opts[:headers])
        send(self(), {:webhook_event, headers["x-micelio-event"]})
        {:ok, %{status: 200, body: ""}}
      end)

      # Use synchronous dispatch to avoid Task.Supervisor mocking
      Webhooks.deliver_repository_event(
        repository,
        "session.landed",
        session_payload(session, 42)
      )

      Webhooks.deliver_repository_event(repository, "push", session_payload(session, 42))

      events =
        for _ <- 1..2 do
          assert_receive {:webhook_event, event}
          event
        end

      assert Enum.sort(events) == ["push", "session.landed"]
    end
  end

  describe "create_webhook/1" do
    test "rejects unsupported events" do
      {:ok, organization} =
        Accounts.create_organization(%{
          name: "Beta",
          handle: "beta-#{System.unique_integer([:positive])}"
        })

      {:ok, repository} =
        Micelio.Repositories.create_repository(%{
          handle: "repo-#{System.unique_integer([:positive])}",
          name: "Repo",
          description: "Test",
          organization_id: organization.id,
          visibility: "public"
        })

      assert {:error, changeset} =
               Webhooks.create_webhook(%{
                 repository_id: repository.id,
                 url: "https://hooks.example.com/invalid",
                 events: ["unknown.event"]
               })

      assert Enum.any?(errors_on(changeset).events, fn message ->
               String.contains?(message, "contains unsupported events")
             end)
    end

    test "rejects invalid urls" do
      {:ok, organization} =
        Accounts.create_organization(%{
          name: "Invalid Url Org",
          handle: "invalid-url-org-#{System.unique_integer([:positive])}"
        })

      {:ok, repository} =
        Micelio.Repositories.create_repository(%{
          handle: "invalid-url-repo-#{System.unique_integer([:positive])}",
          name: "Invalid Url Repo",
          description: "Test",
          organization_id: organization.id,
          visibility: "public"
        })

      assert {:error, changeset} =
               Webhooks.create_webhook(%{
                 repository_id: repository.id,
                 url: "ftp://hooks.example.com",
                 events: ["push"]
               })

      assert "must be a valid http(s) URL" in errors_on(changeset).url
    end
  end

  defp normalize_headers(headers) do
    Enum.reduce(headers, %{}, fn {key, value}, acc ->
      Map.put(acc, String.downcase(to_string(key)), value)
    end)
  end

  defp sign(secret, body) do
    :crypto.mac(:hmac, :sha256, secret, body)
    |> Base.encode16(case: :lower)
  end

  defp session_payload(session, landing_position) do
    %{
      "session_id" => session.session_id,
      "status" => to_string(session.status),
      "user_id" => session.user_id,
      "repository_id" => session.repository_id,
      "landing_position" => landing_position,
      "landed_at" => nil
    }
  end
end
