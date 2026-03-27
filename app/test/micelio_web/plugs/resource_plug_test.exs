defmodule MicelioWeb.ResourcePlugTest do
  # async: false because global Mimic mocking requires exclusive ownership
  use ExUnit.Case, async: false
  use Mimic

  import Mimic
  import Phoenix.ConnTest

  setup :verify_on_exit!
  setup :set_mimic_global

  describe "load_account" do
    test "assigns the account if it exists" do
      conn = build_conn(:get, "/micelio", %{account: "micelio"})
      opts = MicelioWeb.ResourcePlug.init(:load_account)
      account = %Micelio.Accounts.Account{handle: "micelio"}
      expect(Micelio.Accounts, :get_account_by_handle, fn "micelio" -> account end)

      got = MicelioWeb.ResourcePlug.call(conn, opts)

      assert got.assigns[:selected_account] == account
    end
  end

  describe "load_repository" do
    test "assigns nil when no repository param" do
      conn = build_conn(:get, "/micelio", %{account: "micelio"})
      opts = MicelioWeb.ResourcePlug.init(:load_repository)

      got = MicelioWeb.ResourcePlug.call(conn, opts)

      assert got.assigns[:selected_repository] == nil
      assert Map.delete(got.assigns, :selected_repository) == conn.assigns
    end

    test "loads repository when account and repository param exist" do
      conn = build_conn(:get, "/micelio/mic", %{account: "micelio", repository: "mic"})
      opts = MicelioWeb.ResourcePlug.init(:load_repository)

      account = %Micelio.Accounts.Account{handle: "micelio", organization_id: "org-1"}
      conn = Plug.Conn.assign(conn, :selected_account, account)

      repository = %Micelio.Repositories.Repository{handle: "mic", organization_id: "org-1"}
      expect(Micelio.Repositories, :get_repository_by_handle, fn "org-1", "mic" -> repository end)

      got = MicelioWeb.ResourcePlug.call(conn, opts)

      assert got.assigns[:selected_repository] == repository
    end
  end
end
