defmodule Micelio.PromEx do
  use PromEx, otp_app: :micelio

  @impl true
  def plugins do
    [
      PromEx.Plugins.Application,
      PromEx.Plugins.Beam,
      {PromEx.Plugins.Phoenix, router: MicelioWeb.Router, endpoint: MicelioWeb.Endpoint},
      {PromEx.Plugins.Ecto, repos: [Micelio.Repo]}
    ]
  end

  @impl true
  def dashboard_assigns do
    [datasource_id: "prometheus", default_selected_interval: "30s"]
  end

  @impl true
  def dashboards do
    [
      {:prom_ex, "application.json"},
      {:prom_ex, "beam.json"},
      {:prom_ex, "phoenix.json"},
      {:prom_ex, "ecto.json"}
    ]
  end
end
