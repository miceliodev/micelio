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

  def projects_plans(conn, %{"account" => account, "repository" => repository}) do
    conn |> redirect(to: ~p"/#{account}/#{repository}/prs") |> halt()
  end

  def projects_plan_new(conn, %{"account" => account, "repository" => repository}) do
    conn |> redirect(to: ~p"/#{account}/#{repository}/prs/new") |> halt()
  end

  def projects_plan(conn, %{"account" => account, "repository" => repository, "id" => id}) do
    conn |> redirect(to: ~p"/#{account}/#{repository}/prs/#{id}") |> halt()
  end
end
