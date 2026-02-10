defmodule MicelioWeb.Oauth.RegistrationController do
  @behaviour Boruta.Openid.DynamicRegistrationApplication

  use MicelioWeb, :controller

  alias Boruta.Oauth.Client
  alias Boruta.Openid

  def register(%Plug.Conn{} = conn, params) do
    registration_params = build_registration_params(params)
    Openid.register_client(conn, registration_params, __MODULE__)
  end

  @impl Boruta.Openid.DynamicRegistrationApplication
  def client_registered(conn, %Client{} = client) do
    now = DateTime.utc_now() |> DateTime.to_unix()

    conn
    |> put_status(:created)
    |> json(%{
      client_id: client.id,
      client_secret: client.secret,
      client_id_issued_at: now,
      client_secret_expires_at: 0,
      client_name: client.name,
      redirect_uris: client.redirect_uris || [],
      grant_types: client.supported_grant_types || [],
      token_endpoint_auth_method: primary_auth_method(client)
    })
  end

  @impl Boruta.Openid.DynamicRegistrationApplication
  def registration_failure(conn, changeset) do
    conn
    |> put_status(:bad_request)
    |> json(%{error: "invalid_client_metadata", details: format_errors(changeset)})
  end

  defp build_registration_params(params) do
    %{}
    |> maybe_put(params, :redirect_uris)
    |> maybe_put(params, :client_name)
    |> maybe_put(params, :grant_types)
    |> maybe_put(params, :jwks)
    |> maybe_put(params, :jwks_uri)
    |> maybe_put(params, :token_endpoint_auth_method)
  end

  defp maybe_put(acc, params, key) do
    string_key = Atom.to_string(key)

    case Map.fetch(params, string_key) do
      {:ok, value} -> Map.put(acc, key, value)
      :error -> acc
    end
  end

  defp primary_auth_method(%Client{token_endpoint_auth_methods: [method | _]}), do: method
  defp primary_auth_method(_), do: nil

  defp format_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Enum.reduce(opts, msg, fn {key, value}, acc ->
        String.replace(acc, "%{#{key}}", to_string(value))
      end)
    end)
  end
end
