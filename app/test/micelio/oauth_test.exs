defmodule Micelio.OAuthTest do
  use Micelio.DataCase, async: true

  alias Micelio.OAuth

  test "ensure_cli_device_client creates and reuses the built-in hif client" do
    assert {:ok, client} = OAuth.ensure_cli_device_client()
    assert client.client_id == OAuth.cli_client_id()

    assert {:ok, same_client} = OAuth.ensure_cli_device_client()
    assert same_client.id == client.id
    assert same_client.client_id == client.client_id
  end
end
