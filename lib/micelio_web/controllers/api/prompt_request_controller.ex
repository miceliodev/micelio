defmodule MicelioWeb.Api.PromptRequestController do
  use MicelioWeb, :controller

  alias Micelio.Accounts
  alias Micelio.Authorization
  alias Micelio.PromptRequests
  alias Micelio.Repositories

  def create(conn, %{
        "organization_handle" => organization_handle,
        "repository_handle" => repository_handle,
        "prompt_request" => prompt_request_params
      }) do
    with {:ok, user} <- fetch_user(conn),
         {:ok, repository} <- fetch_project(organization_handle, repository_handle),
         :ok <- Authorization.authorize(:repository_read, user, repository),
         {:ok, prompt_request} <-
           PromptRequests.submit_prompt_request(prompt_request_params,
             project: repository,
             user: user,
             validation_async: false,
             flow_opts: prompt_request_flow_opts(conn)
           ) do
      conn
      |> put_status(:created)
      |> json(%{data: prompt_request_payload(prompt_request)})
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
        |> json(%{error: "Not authorized to submit prompt requests"})

      {:error, {:validation_failed, feedback, prompt_request}} ->
        feedback_payload = PromptRequests.format_validation_feedback(feedback)
        feedback_message = PromptRequests.validation_feedback_summary(feedback)

        conn
        |> put_status(:unprocessable_entity)
        |> json(%{
          error: feedback_message,
          feedback: feedback_payload,
          data: prompt_request_payload(prompt_request)
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
    |> json(%{error: "prompt_request payload is required"})
  end

  defp fetch_user(conn) do
    case conn.assigns[:current_user] do
      nil -> {:error, :unauthorized}
      user -> {:ok, user}
    end
  end

  defp prompt_request_flow_opts(conn) do
    case conn.assigns[:prompt_request_flow_opts] do
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

  defp prompt_request_payload(prompt_request) do
    confidence = PromptRequests.confidence_score(prompt_request)

    %{
      id: prompt_request.id,
      repository_id: prompt_request.repository_id,
      user_id: prompt_request.user_id,
      session_id: prompt_request.session_id,
      title: prompt_request.title,
      prompt: prompt_request.prompt,
      result: prompt_request.result,
      system_prompt: prompt_request.system_prompt,
      conversation: prompt_request.conversation,
      origin: origin_value(prompt_request.origin),
      model: prompt_request.model,
      model_version: prompt_request.model_version,
      token_count: prompt_request.token_count,
      confidence_score: confidence.overall,
      confidence_label: confidence.label,
      generated_at: format_datetime(prompt_request.generated_at),
      review_status: review_status_value(prompt_request.review_status),
      reviewed_at: format_datetime(prompt_request.reviewed_at),
      validation_feedback:
        PromptRequests.format_validation_feedback(prompt_request.validation_feedback),
      validation_iterations: prompt_request.validation_iterations,
      execution_environment: prompt_request.execution_environment,
      execution_duration_ms: prompt_request.execution_duration_ms,
      parent_prompt_request_id: prompt_request.parent_prompt_request_id,
      inserted_at: format_datetime(prompt_request.inserted_at),
      updated_at: format_datetime(prompt_request.updated_at)
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
