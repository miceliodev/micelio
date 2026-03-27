defmodule MicelioWeb.Api.PlanController do
  use MicelioWeb, :controller

  alias Micelio.Accounts
  alias Micelio.Authorization
  alias Micelio.Plans
  alias Micelio.Repositories

  def create(conn, %{
        "organization_handle" => organization_handle,
        "repository_handle" => repository_handle,
        "plan" => plan_params
      }) do
    with {:ok, user} <- fetch_user(conn),
         {:ok, repository} <- fetch_project(organization_handle, repository_handle),
         :ok <- Authorization.authorize(:repository_read, user, repository),
         {:ok, plan} <-
           Plans.submit_plan(plan_params,
             project: repository,
             user: user,
             validation_async: false,
             flow_opts: plan_flow_opts(conn)
           ) do
      conn
      |> put_status(:created)
      |> json(%{data: plan_payload(plan)})
    else
      {:error, :unauthorized} ->
        conn
        |> put_status(:unauthorized)
        |> json(%{error: "Authentication required"})

      {:error, :not_found} ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Project not found"})

      {:error, :forbidden} ->
        conn
        |> put_status(:forbidden)
        |> json(%{error: "Not authorized to submit plans"})

      {:error, {:validation_failed, feedback, plan}} ->
        feedback_payload = Plans.format_validation_feedback(feedback)
        feedback_message = Plans.validation_feedback_summary(feedback)

        conn
        |> put_status(:unprocessable_entity)
        |> json(%{
          error: feedback_message,
          feedback: feedback_payload,
          data: plan_payload(plan)
        })

      {:error, %Ecto.Changeset{} = changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: changeset_errors(changeset)})
    end
  end

  def create(conn, _params) do
    conn
    |> put_status(:bad_request)
    |> json(%{error: "plan payload is required"})
  end

  defp fetch_user(conn) do
    case conn.assigns[:current_user] do
      nil -> {:error, :unauthorized}
      user -> {:ok, user}
    end
  end

  defp plan_flow_opts(conn) do
    case conn.assigns[:plan_flow_opts] do
      nil -> []
      opts -> opts
    end
  end

  defp fetch_project(organization_handle, repository_handle) do
    with {:ok, organization} <- Accounts.get_organization_by_handle(organization_handle),
         repository when not is_nil(repository) <-
           Repositories.get_repository_by_handle(organization.id, repository_handle) do
      {:ok, repository}
    else
      nil -> {:error, :not_found}
      {:error, :not_found} -> {:error, :not_found}
    end
  end

  defp plan_payload(plan) do
    confidence = Plans.confidence_score(plan)

    %{
      id: plan.id,
      repository_id: plan.repository_id,
      user_id: plan.user_id,
      session_id: plan.session_id,
      title: plan.title,
      prompt: plan.prompt,
      result: plan.result,
      system_prompt: plan.system_prompt,
      conversation: plan.conversation,
      origin: origin_value(plan.origin),
      model: plan.model,
      model_version: plan.model_version,
      token_count: plan.token_count,
      confidence_score: confidence.overall,
      confidence_label: confidence.label,
      generated_at: format_datetime(plan.generated_at),
      review_status: review_status_value(plan.review_status),
      reviewed_at: format_datetime(plan.reviewed_at),
      validation_feedback: Plans.format_validation_feedback(plan.validation_feedback),
      validation_iterations: plan.validation_iterations,
      execution_environment: plan.execution_environment,
      execution_duration_ms: plan.execution_duration_ms,
      parent_plan_id: plan.parent_plan_id,
      inserted_at: format_datetime(plan.inserted_at),
      updated_at: format_datetime(plan.updated_at)
    }
  end

  defp origin_value(origin) when is_atom(origin), do: Atom.to_string(origin)
  defp origin_value(origin) when is_binary(origin), do: origin
  defp origin_value(_origin), do: nil

  defp review_status_value(status) when is_atom(status), do: Atom.to_string(status)
  defp review_status_value(status) when is_binary(status), do: status
  defp review_status_value(_status), do: nil

  defp format_datetime(nil), do: nil
  defp format_datetime(%DateTime{} = datetime), do: DateTime.to_iso8601(datetime)

  defp changeset_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Enum.reduce(opts, msg, fn {key, value}, acc ->
        String.replace(acc, "%{#{key}}", to_string(value))
      end)
    end)
  end
end
