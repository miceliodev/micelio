defmodule MicelioWeb.ConnCase do
  @moduledoc """
  This module defines the test case to be used by
  tests that require setting up a connection.

  Such tests rely on `Phoenix.ConnTest` and also
  import other functionality to make it easier
  to build common data structures and query the data layer.

  Finally, if the test case interacts with the database,
  we enable the SQL sandbox, so changes done to the database
  are reverted at the end of every test. If you are using
  PostgreSQL, you can even run database tests asynchronously
  by setting `use MicelioWeb.ConnCase, async: true`, although
  this option is not recommended for other databases.
  """

  use ExUnit.CaseTemplate

  using do
    quote do
      use Mimic
      use MicelioWeb, :verified_routes

      import MicelioWeb.ConnCase
      import Phoenix.ConnTest
      import Plug.Conn
      # The default endpoint for testing
      @endpoint MicelioWeb.Endpoint

      # Import conveniences for testing with connections
    end
  end

  setup tags do
    Micelio.DataCase.setup_sandbox(tags)
    {:ok, conn: Phoenix.ConnTest.build_conn()}
  end

  @doc """
  Setup helper that registers and logs in a user.

      setup :register_and_log_in_user

  It stores an updated connection and a user in the
  test context.
  """
  def register_and_log_in_user(%{conn: conn}) do
    user = user_fixture()
    %{conn: log_in_user(conn, user), user: user}
  end

  @doc """
  Logs the given `user` into the `conn`.

  It returns an updated `conn`.
  """
  def log_in_user(conn, user) do
    Plug.Test.init_test_session(conn, %{"user_id" => user.id})
  end

  defp user_fixture(attrs \\ %{}) do
    email = attrs[:email] || "user#{System.unique_integer()}@example.com"
    {:ok, user} = Micelio.Accounts.get_or_create_user_by_email(email)
    user
  end
end
