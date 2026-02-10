defmodule Micelio.Errors.ErrorTest do
  use Micelio.DataCase, async: true

  alias Micelio.Errors.Error

  test "changeset requires core fields" do
    changeset = Error.changeset(%Error{}, %{})

    assert %{
             fingerprint: ["can't be blank"],
             kind: ["can't be blank"],
             message: ["can't be blank"],
             occurred_at: ["can't be blank"],
             first_seen_at: ["can't be blank"],
             last_seen_at: ["can't be blank"]
           } = errors_on(changeset)
  end

  test "changeset accepts valid attributes" do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    attrs = %{
      fingerprint: "exception:RuntimeError:boom",
      kind: :exception,
      message: "boom",
      stacktrace: "stack",
      severity: :error,
      occurred_at: now,
      first_seen_at: now,
      last_seen_at: now,
      occurrence_count: 1
    }

    changeset = Error.changeset(%Error{}, attrs)
    assert changeset.valid?

    error = Ecto.Changeset.apply_changes(changeset)
    assert error.kind == :exception
    assert error.severity == :error
    assert error.metadata == %{}
    assert error.context == %{}
  end

  test "changeset rejects non-positive occurrence counts" do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    attrs = %{
      fingerprint: "exception:RuntimeError:boom",
      kind: :exception,
      message: "boom",
      severity: :error,
      occurred_at: now,
      first_seen_at: now,
      last_seen_at: now,
      occurrence_count: 0
    }

    changeset = Error.changeset(%Error{}, attrs)

    assert %{occurrence_count: ["must be greater than 0"]} = errors_on(changeset)
  end
end
