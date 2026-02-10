defmodule MicelioWeb.PromptRequestLive.Index do
  use MicelioWeb, :live_view

  alias Micelio.Authorization
  alias Micelio.ContributionConfidence
  alias Micelio.PromptRequests
  alias Micelio.PromptRequests.PromptRequest
  alias Micelio.Repositories
  alias MicelioWeb.PageMeta

  @impl true
  def mount(%{"account" => org_handle, "repository" => repository_handle}, _session, socket) do
    with {:ok, repository, organization} <-
           Repositories.get_repository_for_user_by_handle(
             socket.assigns.current_user,
             org_handle,
             repository_handle
           ),
         :ok <- Authorization.authorize(:repository_read, socket.assigns.current_user, repository) do
      prompt_requests = PromptRequests.list_prompt_requests_for_repository(repository)
      confidence_scores = PromptRequests.confidence_scores(prompt_requests)

      socket =
        socket
        |> assign(:page_title, "Prompt Requests")
        |> PageMeta.assign(
          description: "Prompt requests for #{repository.name}.",
          canonical_url:
            url(~p"/#{organization.account.handle}/#{repository.handle}/prompt-requests")
        )
        |> assign(:repository, repository)
        |> assign(:organization, organization)
        |> assign(:prompt_requests, prompt_requests)
        |> assign(:confidence_scores, confidence_scores)

      {:ok, socket}
    else
      _ ->
        {:ok,
         socket
         |> put_flash(:error, "Project not found or access denied.")
         |> push_navigate(to: ~p"/repositories")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      current_scope={@current_scope}
      current_user={@current_user}
    >
      <.repository_header
        account_handle={@organization.account.handle}
        repository_handle={@repository.handle}
        active_tab={:sessions}
      >
        <div class="prompt-requests-container">
          <.header>
            Prompt Requests
            <:subtitle>
              <div class="prompt-requests-subtitle">
                For {@organization.account.handle}/{@repository.handle}
              </div>
            </:subtitle>
            <:actions>
              <.link
                navigate={
                  ~p"/#{@organization.account.handle}/#{@repository.handle}/prompt-requests/new"
                }
                class="prompt-request-button"
                id="new-prompt-request"
              >
                New prompt request
              </.link>
            </:actions>
          </.header>

          <%= if Enum.empty?(@prompt_requests) do %>
            <div class="prompt-requests-empty">
              <h2>No prompt requests yet</h2>
              <p>Start a contribution by sharing the prompt and the generated result.</p>
            </div>
          <% else %>
            <div class="prompt-requests-list" id="prompt-request-list">
              <%= for prompt_request <- @prompt_requests do %>
                <.link
                  navigate={
                    ~p"/#{@organization.account.handle}/#{@repository.handle}/prompt-requests/#{prompt_request.id}"
                  }
                  class="prompt-request-card"
                  id={"prompt-request-#{prompt_request.id}"}
                >
                  <div class="prompt-request-card-title">
                    {prompt_request.title}
                    <span class={"badge badge--caps prompt-request-origin prompt-request-origin-#{origin_value(prompt_request.origin)}"}>
                      {origin_label(prompt_request.origin)}
                    </span>
                  </div>
                  <div class="prompt-request-card-meta">
                    <span>Model: {format_model(prompt_request.model)}</span>
                    <span>Version: {format_model(prompt_request.model_version)}</span>
                    <span>Tokens: {format_token_count(prompt_request.token_count)}</span>
                    <span>Submitted by {prompt_request.user.email}</span>
                    <span>
                      Confidence: {format_confidence(Map.get(@confidence_scores, prompt_request.id))}
                    </span>
                  </div>
                  <div class="prompt-request-card-meta">
                    <span>Generated: {format_datetime(prompt_request.generated_at)}</span>
                    <span>Submitted: {format_datetime(prompt_request.inserted_at)}</span>
                    <span>
                      Lag: {format_generation_lag(
                        prompt_request.generated_at,
                        prompt_request.inserted_at
                      )}
                    </span>
                    <span>
                      Attestation: {attestation_label(
                        PromptRequests.attestation_status(prompt_request)
                      )}
                    </span>
                  </div>
                </.link>
              <% end %>
            </div>
          <% end %>
        </div>
      </.repository_header>
    </Layouts.app>
    """
  end

  defp origin_label(origin), do: PromptRequest.origin_label(origin)

  defp origin_value(origin) when is_atom(origin), do: Atom.to_string(origin)
  defp origin_value(origin) when is_binary(origin), do: origin
  defp origin_value(_), do: "unknown"

  defp format_model(nil), do: "n/a"
  defp format_model(""), do: "n/a"
  defp format_model(value), do: value

  defp format_token_count(nil), do: "n/a"
  defp format_token_count(value) when is_integer(value), do: Integer.to_string(value)

  defp format_confidence(%ContributionConfidence.Score{overall: overall, label: label}) do
    "#{overall} (#{label})"
  end

  defp format_confidence(_score), do: "n/a"

  defp format_datetime(nil), do: "n/a"

  defp format_datetime(%DateTime{} = datetime) do
    datetime
    |> DateTime.truncate(:second)
    |> Calendar.strftime("%Y-%m-%d %H:%M:%S UTC")
  end

  defp format_datetime(%NaiveDateTime{} = datetime) do
    datetime
    |> NaiveDateTime.truncate(:second)
    |> Calendar.strftime("%Y-%m-%d %H:%M:%S")
  end

  defp format_generation_lag(%DateTime{} = generated_at, %DateTime{} = submitted_at) do
    diff_seconds = DateTime.diff(submitted_at, generated_at, :second)

    cond do
      diff_seconds < 0 ->
        "n/a"

      diff_seconds < 60 ->
        "<1m"

      diff_seconds < 3600 ->
        "#{div(diff_seconds, 60)}m"

      diff_seconds < 86_400 ->
        hours = div(diff_seconds, 3600)
        minutes = div(rem(diff_seconds, 3600), 60)
        "#{hours}h #{minutes}m"

      true ->
        days = div(diff_seconds, 86_400)
        hours = div(rem(diff_seconds, 86_400), 3600)
        "#{days}d #{hours}h"
    end
  end

  defp format_generation_lag(_, _), do: "n/a"

  defp attestation_label(:verified), do: "Verified"
  defp attestation_label(:invalid), do: "Invalid"
  defp attestation_label(:missing), do: "Missing"
end
