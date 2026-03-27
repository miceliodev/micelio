defmodule Micelio.Errors.NotificationEmailTest do
  use ExUnit.Case, async: true

  alias Micelio.Errors.Error
  alias Micelio.Errors.NotificationEmail

  test "includes first seen timestamp in email bodies" do
    first_seen_at = DateTime.new!(~D[2025-02-04], ~T[12:34:56], "Etc/UTC")
    occurred_at = DateTime.new!(~D[2025-02-04], ~T[12:35:56], "Etc/UTC")

    error = %Error{
      id: Ecto.UUID.generate(),
      fingerprint: "abc123",
      kind: :exception,
      message: "boom",
      severity: :error,
      occurrence_count: 3,
      first_seen_at: first_seen_at,
      occurred_at: occurred_at
    }

    email = NotificationEmail.error_email("admin@example.com", error, :new_error)
    timestamp = DateTime.to_iso8601(first_seen_at)

    assert String.contains?(email.html_body, "First seen: #{timestamp}")
    assert String.contains?(email.text_body, "First seen: #{timestamp}")
  end
end
