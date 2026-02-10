defmodule MicelioWeb.ApiSpec do
  @behaviour OpenApiSpex.OpenApi

  alias OpenApiSpex.{Info, OpenApi, Server}

  @impl OpenApiSpex.OpenApi
  def spec do
    %OpenApi{
      servers: [
        %Server{url: "/"}
      ],
      info: %Info{
        title: "Micelio API",
        version: api_version()
      },
      paths: OpenApiSpex.Paths.from_router(MicelioWeb.Router)
    }
    |> OpenApiSpex.resolve_schema_modules()
  end

  defp api_version do
    Application.spec(:micelio, :vsn) |> to_string()
  end
end
