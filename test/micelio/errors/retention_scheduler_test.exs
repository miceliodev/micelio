defmodule Micelio.Errors.RetentionSchedulerTest do
  use ExUnit.Case, async: true

  import Mimic

  alias Micelio.Errors.Retention
  alias Micelio.Errors.RetentionScheduler

  setup :verify_on_exit!

  setup do
    Mimic.copy(Retention)
    :ok
  end

  test "run_cleanup runs retention directly when Oban is disabled" do
    errors_config = [retention_oban_enabled: false]

    expect(Retention, :run, fn opts ->
      assert opts[:errors] == errors_config
      {:ok, %{}}
    end)

    assert {:ok, %{}} = RetentionScheduler.run_cleanup(errors: errors_config)
  end

  test "run_cleanup runs retention directly when Oban is enabled but unavailable" do
    errors_config = [retention_oban_enabled: true]

    expect(Retention, :run, fn opts ->
      assert opts[:errors] == errors_config
      {:ok, %{}}
    end)

    assert {:ok, %{}} = RetentionScheduler.run_cleanup(errors: errors_config)
  end
end
