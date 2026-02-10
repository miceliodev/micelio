defmodule Micelio.Errors.RetentionJobTest do
  use ExUnit.Case, async: true

  import Mimic

  alias Micelio.Errors.Retention
  alias Micelio.Errors.RetentionJob

  setup :verify_on_exit!

  setup do
    Mimic.copy(Retention)
    :ok
  end

  test "perform/1 runs retention cleanup" do
    expect(Retention, :run, fn -> {:ok, %{}} end)

    assert {:ok, %{}} = RetentionJob.perform(%{})
  end
end
