defmodule MicelioWeb.Browser.RedirectController do
  use MicelioWeb, :controller

  def projects_index(conn, _params) do
    conn |> redirect(to: ~p"/repositories") |> halt()
  end

  def projects_new(conn, _params) do
    conn |> redirect(to: ~p"/repositories/new") |> halt()
  end

  def projects_show(conn, %{"account" => account, "repository" => repository}) do
    conn |> redirect(to: ~p"/#{account}/#{repository}") |> halt()
  end

  def projects_edit(conn, %{"account" => account, "repository" => repository}) do
    conn |> redirect(to: ~p"/#{account}/#{repository}/edit") |> halt()
  end

  def projects_sessions(conn, %{"account" => account, "repository" => repository}) do
    conn |> redirect(to: ~p"/#{account}/#{repository}/sessions") |> halt()
  end

  def projects_session(conn, %{"account" => account, "repository" => repository, "id" => id}) do
    conn |> redirect(to: ~p"/#{account}/#{repository}/sessions/#{id}") |> halt()
  end

  def projects_prompt_requests(conn, %{"account" => account, "repository" => repository}) do
    conn |> redirect(to: ~p"/#{account}/#{repository}/prompt-requests") |> halt()
  end

  def projects_prompt_request_new(conn, %{"account" => account, "repository" => repository}) do
    conn |> redirect(to: ~p"/#{account}/#{repository}/prompt-requests/new") |> halt()
  end

  def projects_prompt_request(conn, %{
        "account" => account,
        "repository" => repository,
        "id" => id
      }) do
    conn |> redirect(to: ~p"/#{account}/#{repository}/prompt-requests/#{id}") |> halt()
  end
end
