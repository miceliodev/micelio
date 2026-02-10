defmodule Micelio.OAuth.TokenGenerator do
  @moduledoc false
  @behaviour Boruta.Oauth.TokenGenerator

  @impl Boruta.Oauth.TokenGenerator
  def generate(_token_type, _token) do
    :crypto.strong_rand_bytes(32) |> Base.url_encode64(padding: false)
  end

  @impl Boruta.Oauth.TokenGenerator
  def secret(client) do
    Boruta.TokenGenerator.secret(client)
  end

  @impl Boruta.Oauth.TokenGenerator
  def tx_code_input_mode, do: :numeric

  @impl Boruta.Oauth.TokenGenerator
  def tx_code_length, do: 6
end
