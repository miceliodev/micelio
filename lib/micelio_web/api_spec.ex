defmodule MicelioWeb.ApiSpec do
  @behaviour OpenApiSpex.OpenApi

  alias Micelio.OAuth.Scopes
  alias OpenApiSpex.{Components, Info, OpenApi, SecurityScheme, Server}

  @impl OpenApiSpex.OpenApi
  def spec do
    %OpenApi{
      servers: [
        %Server{url: "/"}
      ],
      info: %Info{
        title: "Micelio API",
        version: api_version(),
        description: "REST API for the Micelio forge platform."
      },
      components: %Components{
        securitySchemes: %{
          "bearer" => %SecurityScheme{
            type: "http",
            scheme: "bearer",
            bearerFormat: "opaque",
            description:
              "OAuth2 access token. Obtain via device flow (POST /auth/device) or dynamic client registration (POST /oauth/register)."
          }
        }
      },
      security: [%{"bearer" => []}],
      paths: OpenApiSpex.Paths.from_router(MicelioWeb.Router)
    }
    |> OpenApiSpex.resolve_schema_modules()
  end

  @doc """
  Returns scope descriptions for use in documentation.
  """
  def scope_descriptions, do: Scopes.descriptions()

  defp api_version do
    Application.spec(:micelio, :vsn) |> to_string()
  end
end
