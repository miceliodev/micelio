defmodule Micelio.Sandboxes.Watchdog do
  @moduledoc """
  Periodically checks running sandbox sessions and terminates expired ones.
  """

  use GenServer

  import Ecto.Query, warn: false

  alias Micelio.Plans
  alias Micelio.Plans.Plan
  alias Micelio.Repo
  alias Micelio.Sandboxes.Limits

  require Logger

  @check_interval_ms :timer.seconds(60)

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    schedule_check()
    {:ok, %{}}
  end

  @impl true
  def handle_info(:check_expired, state) do
    expire_sessions()
    schedule_check()
    {:noreply, state}
  end

  defp schedule_check do
    Process.send_after(self(), :check_expired, @check_interval_ms)
  end

  defp expire_sessions do
    Plan
    |> where([p], p.sandbox_status == "running")
    |> Repo.all()
    |> Enum.filter(&Limits.session_expired?/1)
    |> Enum.each(fn plan ->
      Logger.info("Watchdog: expiring sandbox session for plan #{plan.id}")

      case Plans.stop_agentic_session(plan) do
        {:ok, _} ->
          :ok

        {:error, reason} ->
          Logger.warning("Watchdog: failed to stop plan #{plan.id}: #{inspect(reason)}")
      end
    end)
  end
end
