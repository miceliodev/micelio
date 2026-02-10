defmodule MicelioWeb.ErrorBoundaryComponentTest do
  use MicelioWeb.ConnCase, async: false

  import Micelio.ErrorBoundary, only: [error_boundary: 1]
  import Phoenix.LiveViewTest

  alias Micelio.Errors.Error
  alias Micelio.Repo

  setup do
    errors_config = [
      capture_enabled: true,
      dedupe_window_seconds: 0,
      capture_async: false,
      capture_rate_limit_per_kind_per_minute: 1_000,
      capture_rate_limit_total_per_minute: 1_000
    ]

    start_supervised!(Micelio.Errors.RateLimiter)

    on_exit(fn ->
      Micelio.Errors.RateLimiter.reset!()
    end)

    {:ok, errors_config: errors_config}
  end

  test "renders inner content when no error is raised", %{errors_config: errors_config} do
    html =
      render_component(&error_boundary/1,
        id: "boundary",
        retry_path: "/retry",
        capture_async: false,
        errors: errors_config,
        inner_block: [%{__slot__: :inner_block, inner_block: fn _, _ -> "All good" end}]
      )

    assert html =~ "All good"
    refute html =~ "error-boundary-title"
  end

  test "captures render exceptions and shows fallback", %{errors_config: errors_config} do
    Repo.delete_all(Error)

    html =
      render_component(&error_boundary/1,
        id: "boundary",
        retry_path: "/retry",
        capture_async: false,
        errors: errors_config,
        context: %{route: "/boom", params: %{"oops" => "1"}},
        inner_block: [
          %{__slot__: :inner_block, inner_block: fn _, _ -> raise "boom" end}
        ]
      )

    assert html =~ "Something went wrong"
    assert html =~ "Retry"

    [error] = Repo.all(Error)
    assert error.kind == :liveview_crash
    assert error.message =~ "boom"
    assert error.context["route"] == "/boom"
    assert error.context["params"]["oops"] == "1"
  end

  test "renders fallback for exits and captures the reason", %{errors_config: errors_config} do
    Repo.delete_all(Error)

    html =
      render_component(&error_boundary/1,
        id: "boundary-exit",
        retry_path: "/retry",
        capture_async: false,
        errors: errors_config,
        context: %{route: "/exit", params: %{}},
        inner_block: [
          %{__slot__: :inner_block, inner_block: fn _, _ -> exit(:boom) end}
        ]
      )

    assert html =~ "Something went wrong"

    [error] = Repo.all(Error)
    assert error.kind == :liveview_crash
    assert error.message =~ "LiveView exited"
  end
end
