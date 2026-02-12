defmodule Micelio.PromptRequests do
  @moduledoc """
  Context for prompt request contributions.
  """

  import Ecto.Query, warn: false

  alias Ecto.Multi
  alias Micelio.AITokens
  alias Micelio.ContributionConfidence
  alias Micelio.PromptRequests.{PromptRequest, PromptSuggestion, PromptTemplate}
  alias Micelio.Repo
  alias Micelio.Sessions.Session
  alias Micelio.ValidationEnvironments
  alias Micelio.ValidationEnvironments.ValidationRun
  alias MicelioWeb.Endpoint

  def confidence_score(%PromptRequest{} = prompt_request, opts \\ []) do
    ContributionConfidence.score_for_prompt_request(prompt_request, opts)
  end

  def confidence_scores(prompt_requests, opts \\ []) when is_list(prompt_requests) do
    ContributionConfidence.scores_for_prompt_requests(prompt_requests, opts)
  end

  def list_prompt_requests_for_repository(repository) do
    PromptRequest
    |> where([prompt_request], prompt_request.repository_id == ^repository.id)
    |> order_by([prompt_request], desc: prompt_request.number, desc: prompt_request.inserted_at)
    |> preload(:user)
    |> Repo.all()
  end

  def list_prompt_registry(opts \\ []) do
    search = Keyword.get(opts, :search)
    review_status = Keyword.get(opts, :review_status)
    curated_only = Keyword.get(opts, :curated_only, false)
    limit = Keyword.get(opts, :limit)

    PromptRequest
    |> order_by([prompt_request], desc: prompt_request.inserted_at)
    |> maybe_filter_registry_search(search)
    |> maybe_filter_review_status(review_status)
    |> maybe_filter_curated(curated_only)
    |> maybe_limit_registry(limit)
    |> preload([:user, :prompt_template, :curated_by, repository: [organization: :account]])
    |> Repo.all()
  end

  def count_prompt_requests_for_repository(repository) do
    PromptRequest
    |> where([prompt_request], prompt_request.repository_id == ^repository.id)
    |> select([prompt_request], count(prompt_request.id))
    |> Repo.one()
  end

  def get_prompt_request_for_repository(repository, id) do
    PromptRequest
    |> where(
      [prompt_request],
      prompt_request.repository_id == ^repository.id and prompt_request.id == ^id
    )
    |> preload([:user, :parent_prompt_request, :prompt_template, :curated_by, suggestions: :user])
    |> Repo.one()
  end

  def get_prompt_request_by_number(repository, number) do
    PromptRequest
    |> where(
      [prompt_request],
      prompt_request.repository_id == ^repository.id and prompt_request.number == ^number
    )
    |> preload(:user)
    |> Repo.one()
  end

  def create_simple_prompt_request(attrs, opts) do
    repository = Keyword.fetch!(opts, :repository)
    user = Keyword.fetch!(opts, :user)

    Repo.transaction(fn ->
      number = next_number_for_repository(repository)

      result =
        %PromptRequest{}
        |> PromptRequest.simple_changeset(attrs)
        |> Ecto.Changeset.put_change(:repository_id, repository.id)
        |> Ecto.Changeset.put_change(:user_id, user.id)
        |> Ecto.Changeset.put_change(:number, number)
        |> Ecto.Changeset.put_change(:origin, :human)
        |> Repo.insert()

      case result do
        {:ok, prompt_request} -> prompt_request
        {:error, changeset} -> Repo.rollback(changeset)
      end
    end)
  end

  defp next_number_for_repository(repository) do
    # Use advisory lock to prevent race conditions on number assignment
    lock_key = :erlang.phash2({"prompt_request_number", repository.id})
    Repo.query!("SELECT pg_advisory_xact_lock($1)", [lock_key])

    current_max =
      PromptRequest
      |> where([pr], pr.repository_id == ^repository.id)
      |> select([pr], max(pr.number))
      |> Repo.one()

    (current_max || 0) + 1
  end

  def change_prompt_request(%PromptRequest{} = prompt_request, attrs \\ %{}) do
    PromptRequest.changeset(prompt_request, attrs)
  end

  def change_simple_prompt_request(%PromptRequest{} = prompt_request, attrs \\ %{}) do
    PromptRequest.simple_changeset(prompt_request, attrs)
  end

  def update_prompt_request(%PromptRequest{} = prompt_request, attrs) do
    prompt_request
    |> PromptRequest.simple_changeset(attrs)
    |> Repo.update()
  end

  def close_prompt_request(%PromptRequest{} = prompt_request) do
    prompt_request
    |> PromptRequest.status_changeset("closed")
    |> Repo.update()
  end

  def reopen_prompt_request(%PromptRequest{} = prompt_request) do
    prompt_request
    |> PromptRequest.status_changeset("open")
    |> Repo.update()
  end

  def curate_prompt_request(%PromptRequest{} = prompt_request, curator) do
    attrs = %{
      curated_at: DateTime.utc_now() |> DateTime.truncate(:second),
      curated_by_id: curator.id
    }

    prompt_request
    |> PromptRequest.curation_changeset(attrs)
    |> Repo.update()
  end

  def list_prompt_templates(opts \\ []) do
    only_approved = Keyword.get(opts, :only_approved, false)

    PromptTemplate
    |> order_by([prompt_template], asc: prompt_template.name)
    |> maybe_filter_approved_templates(only_approved)
    |> Repo.all()
  end

  def get_prompt_template(id) do
    Repo.get(PromptTemplate, id)
  end

  def change_prompt_template(%PromptTemplate{} = prompt_template, attrs \\ %{}) do
    PromptTemplate.changeset(prompt_template, attrs)
  end

  def create_prompt_template(attrs, opts) do
    created_by = Keyword.fetch!(opts, :created_by)

    %PromptTemplate{}
    |> PromptTemplate.changeset(attrs)
    |> Ecto.Changeset.put_change(:created_by_id, created_by.id)
    |> Repo.insert()
  end

  def approve_prompt_template(%PromptTemplate{} = prompt_template, approver) do
    attrs = %{
      approved_at: DateTime.utc_now() |> DateTime.truncate(:second),
      approved_by_id: approver.id
    }

    prompt_template
    |> PromptTemplate.approval_changeset(attrs)
    |> Repo.update()
  end

  def create_prompt_request(attrs, opts) do
    repository = Keyword.fetch!(opts, :repository)
    user = Keyword.fetch!(opts, :user)

    %PromptRequest{}
    |> PromptRequest.changeset(attrs)
    |> Ecto.Changeset.put_change(:repository_id, repository.id)
    |> Ecto.Changeset.put_change(:user_id, user.id)
    |> ensure_generation_depth(max_generation_depth(opts))
    |> put_attestation()
    |> Repo.insert()
  end

  def submit_prompt_request(attrs, opts) do
    repository = Keyword.fetch!(opts, :repository)
    user = Keyword.fetch!(opts, :user)

    flow_opts =
      Keyword.get(opts, :flow_opts, Application.get_env(:micelio, :prompt_request_flow, []))

    validation_enabled =
      Keyword.get(opts, :validation_enabled, Keyword.get(flow_opts, :validation_enabled, true))

    validation_async =
      Keyword.get(opts, :validation_async, Keyword.get(flow_opts, :validation_async, true))

    validation_opts =
      Keyword.get(opts, :validation_opts, Keyword.get(flow_opts, :validation_opts, []))

    task_budget_amount =
      Keyword.get(opts, :task_budget_amount, Keyword.get(flow_opts, :task_budget_amount))

    with {:ok, prompt_request} <-
           create_prompt_request(attrs, repository: repository, user: user),
         :ok <- maybe_allocate_task_budget(prompt_request, task_budget_amount) do
      cond do
        validation_enabled and validation_async ->
          run_prompt_request_validation(prompt_request, validation_opts, true)
          {:ok, prompt_request}

        validation_enabled ->
          finalize_prompt_request_validation(prompt_request, validation_opts)

        true ->
          {:ok, prompt_request}
      end
    end
  end

  def list_prompt_suggestions(%PromptRequest{} = prompt_request) do
    PromptSuggestion
    |> where([prompt_suggestion], prompt_suggestion.prompt_request_id == ^prompt_request.id)
    |> order_by([prompt_suggestion], asc: prompt_suggestion.inserted_at)
    |> preload(:user)
    |> Repo.all()
  end

  def change_prompt_suggestion(%PromptSuggestion{} = prompt_suggestion, attrs \\ %{}) do
    PromptSuggestion.changeset(prompt_suggestion, attrs)
  end

  def create_prompt_suggestion(%PromptRequest{} = prompt_request, attrs, opts) do
    user = Keyword.fetch!(opts, :user)

    Multi.new()
    |> Multi.insert(
      :prompt_suggestion,
      %PromptSuggestion{}
      |> PromptSuggestion.changeset(attrs)
      |> Ecto.Changeset.put_change(:prompt_request_id, prompt_request.id)
      |> Ecto.Changeset.put_change(:user_id, user.id)
    )
    |> Multi.run(:token_earning, fn repo, %{prompt_suggestion: suggestion} ->
      AITokens.ensure_prompt_suggestion_earning(repo, suggestion, prompt_request)
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{prompt_suggestion: suggestion}} ->
        {:ok, suggestion}

      {:error, :prompt_suggestion, %Ecto.Changeset{} = changeset, _changes} ->
        {:error, changeset}

      {:error, :token_earning, %Ecto.Changeset{} = changeset, _changes} ->
        {:error, changeset}
    end
  end

  def list_validation_runs(%PromptRequest{} = prompt_request) do
    ValidationEnvironments.list_runs_for_prompt_request(prompt_request)
  end

  def format_validation_feedback(nil), do: nil

  def format_validation_feedback(%{} = feedback), do: feedback

  def format_validation_feedback(feedback) when is_binary(feedback) do
    case Jason.decode(feedback) do
      {:ok, decoded} when is_map(decoded) -> decoded
      _ -> %{"summary" => feedback}
    end
  end

  def format_validation_feedback(_feedback), do: %{"summary" => "Validation failed."}

  def validation_feedback_summary(feedback) do
    case format_validation_feedback(feedback) do
      nil ->
        "Validation failed."

      %{} = formatted ->
        Map.get(formatted, "summary") || Map.get(formatted, :summary) || "Validation failed."

      other ->
        to_string(other)
    end
  end

  def run_validation(%PromptRequest{} = prompt_request, opts \\ []) do
    config_opts = Application.get_env(:micelio, :validation_environments, [])

    ValidationEnvironments.run_for_prompt_request(
      prompt_request,
      Keyword.merge(config_opts, opts)
    )
  end

  def run_validation_async(%PromptRequest{} = prompt_request, notify_pid, opts \\ []) do
    Task.Supervisor.start_child(Micelio.ValidationEnvironments.Supervisor, fn ->
      finalize_prompt_request_validation(
        prompt_request,
        Keyword.put(opts, :notify_pid, notify_pid)
      )
    end)
  end

  def review_prompt_request(%PromptRequest{} = prompt_request, reviewer, status)
      when status in [:accepted, :rejected, :pending] do
    attrs =
      case status do
        :pending ->
          %{review_status: status, reviewed_at: nil, reviewed_by_id: nil}

        _ ->
          %{
            review_status: status,
            reviewed_at: DateTime.utc_now() |> DateTime.truncate(:second),
            reviewed_by_id: reviewer && reviewer.id
          }
      end

    should_award? = status == :accepted and prompt_request.review_status != :accepted

    Multi.new()
    |> Multi.update(:prompt_request, PromptRequest.review_changeset(prompt_request, attrs))
    |> Multi.run(:prompt_request_session, fn repo, %{prompt_request: updated} ->
      maybe_create_prompt_request_session(repo, updated)
    end)
    |> maybe_award_prompt_request_earning(should_award?)
    |> Repo.transaction()
    |> case do
      {:ok, %{prompt_request_session: updated}} ->
        {:ok, updated}

      {:error, :prompt_request, %Ecto.Changeset{} = changeset, _changes} ->
        {:error, changeset}

      {:error, :prompt_request_session, reason, _changes} ->
        {:error, reason}

      {:error, :token_earning, reason, _changes} ->
        {:error, reason}
    end
  end

  def attestation_status(%PromptRequest{} = prompt_request) do
    case prompt_request.attestation do
      %{"signature" => signature} when is_binary(signature) ->
        if signature == sign_attestation(PromptRequest.attestation_payload(prompt_request)) do
          :verified
        else
          :invalid
        end

      _ ->
        :missing
    end
  end

  def lineage(%PromptRequest{} = prompt_request, opts \\ []) do
    max_depth = Keyword.get(opts, :max_depth, 5)
    build_lineage(prompt_request.parent_prompt_request_id, max_depth, [])
  end

  defp put_attestation(%Ecto.Changeset{valid?: true} = changeset) do
    payload = PromptRequest.attestation_payload(Ecto.Changeset.apply_changes(changeset))

    attestation = %{
      "signature" => sign_attestation(payload),
      "payload" => payload,
      "signed_at" => DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601()
    }

    Ecto.Changeset.put_change(changeset, :attestation, attestation)
  end

  defp put_attestation(changeset), do: changeset

  defp maybe_award_prompt_request_earning(%Multi{} = multi, true) do
    Multi.run(multi, :token_earning, fn repo, %{prompt_request: prompt_request} ->
      AITokens.ensure_prompt_request_earning(repo, prompt_request)
    end)
  end

  defp maybe_award_prompt_request_earning(%Multi{} = multi, false), do: multi

  defp maybe_allocate_task_budget(_prompt_request, nil), do: :ok

  defp maybe_allocate_task_budget(%PromptRequest{} = prompt_request, amount) do
    case AITokens.upsert_task_budget(prompt_request, %{"amount" => amount}) do
      {:ok, _budget, _pool} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp max_generation_depth(opts) do
    Keyword.get(opts, :max_generation_depth, prompt_request_max_generation_depth())
  end

  defp prompt_request_max_generation_depth do
    :micelio
    |> Application.get_env(:prompt_requests, [])
    |> Keyword.get(:max_generation_depth, 3)
  end

  defp ensure_generation_depth(%Ecto.Changeset{} = changeset, max_depth)
       when is_integer(max_depth) and max_depth > 0 do
    parent_id = Ecto.Changeset.get_field(changeset, :parent_prompt_request_id)

    case parent_id do
      nil ->
        changeset

      parent_id ->
        parent_depth = prompt_request_depth(parent_id)

        if parent_depth + 1 > max_depth do
          Ecto.Changeset.add_error(
            changeset,
            :parent_prompt_request_id,
            "exceeds max generation depth"
          )
        else
          changeset
        end
    end
  end

  defp ensure_generation_depth(%Ecto.Changeset{} = changeset, _max_depth), do: changeset

  defp prompt_request_depth(parent_id) do
    prompt_request_depth(parent_id, 0)
  end

  defp prompt_request_depth(nil, depth), do: depth

  defp prompt_request_depth(parent_id, depth) do
    case Repo.get(PromptRequest, parent_id) do
      nil -> depth
      parent -> prompt_request_depth(parent.parent_prompt_request_id, depth + 1)
    end
  end

  defp build_lineage(nil, _depth, acc), do: acc
  defp build_lineage(_parent_id, 0, acc), do: acc

  defp build_lineage(parent_id, depth, acc) do
    case Repo.get(PromptRequest, parent_id) do
      nil ->
        acc

      parent ->
        build_lineage(parent.parent_prompt_request_id, depth - 1, [parent | acc])
    end
  end

  defp sign_attestation(payload) do
    secret = Endpoint.config(:secret_key_base) || raise "secret_key_base is required"
    data = Jason.encode!(payload)
    :crypto.mac(:hmac, :sha256, secret, data) |> Base.encode16(case: :lower)
  end

  defp run_prompt_request_validation(%PromptRequest{} = prompt_request, validation_opts, true) do
    Task.Supervisor.start_child(Micelio.ValidationEnvironments.Supervisor, fn ->
      finalize_prompt_request_validation(prompt_request, validation_opts)
    end)

    :ok
  end

  defp finalize_prompt_request_validation(%PromptRequest{} = prompt_request, validation_opts) do
    case run_validation(prompt_request, validation_opts) do
      {:ok, run} ->
        prompt_request = Repo.preload(prompt_request, :user)

        confidence_score =
          ContributionConfidence.score_for_prompt_request(prompt_request, validation_run: run)

        if ContributionConfidence.auto_accept?(confidence_score) do
          accept_prompt_request(prompt_request, validation_iteration_count(prompt_request))
        else
          update_validation_state(prompt_request, nil, validation_iteration_count(prompt_request))
        end

      {:error, %ValidationRun{} = run} ->
        feedback = validation_feedback(prompt_request, run)
        fail_prompt_request_validation(prompt_request, feedback, reject?: true)

      {:error, reason} ->
        feedback = validation_feedback(prompt_request, reason)
        fail_prompt_request_validation(prompt_request, feedback)
    end
  end

  defp accept_prompt_request(%PromptRequest{} = prompt_request, iterations) do
    prompt_request = Repo.get(PromptRequest, prompt_request.id) || prompt_request

    case review_prompt_request(prompt_request, nil, :accepted) do
      {:ok, updated} ->
        update_validation_state(updated, nil, iterations)

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp update_validation_state(%PromptRequest{} = prompt_request, feedback, iterations) do
    attrs = %{
      validation_feedback: encode_validation_feedback(feedback),
      validation_iterations: iterations
    }

    prompt_request
    |> Ecto.Changeset.change(attrs)
    |> Repo.update()
  end

  defp fail_prompt_request_validation(%PromptRequest{} = prompt_request, feedback, opts \\ []) do
    prompt_request = Repo.get(PromptRequest, prompt_request.id) || prompt_request
    reject? = Keyword.get(opts, :reject?, false)

    prompt_request =
      if reject? do
        case maybe_reject_prompt_request(prompt_request) do
          {:ok, updated} -> updated
          {:error, _reason} -> prompt_request
        end
      else
        prompt_request
      end

    case update_validation_state(
           prompt_request,
           feedback,
           validation_iteration_count(prompt_request)
         ) do
      {:ok, updated} -> {:error, {:validation_failed, feedback, updated}}
      {:error, _changeset} -> {:error, {:validation_failed, feedback, prompt_request}}
    end
  end

  defp maybe_reject_prompt_request(%PromptRequest{review_status: :accepted} = prompt_request),
    do: {:ok, prompt_request}

  defp maybe_reject_prompt_request(%PromptRequest{review_status: :rejected} = prompt_request),
    do: {:ok, prompt_request}

  defp maybe_reject_prompt_request(%PromptRequest{} = prompt_request) do
    review_prompt_request(prompt_request, nil, :rejected)
  end

  defp validation_feedback(%PromptRequest{} = prompt_request, %ValidationRun{} = run) do
    summary = validation_summary_for_run(run)

    base =
      base_validation_feedback(prompt_request,
        summary: summary,
        status: "failed"
      )

    base
    |> Map.merge(quality_score_payload(run))
    |> Map.merge(failure_payload(run))
    |> Map.merge(suggested_fixes_payload(run))
    |> Map.put("validation_run_id", run.id)
  end

  defp validation_feedback(%PromptRequest{} = prompt_request, :missing_budget) do
    base_validation_feedback(prompt_request,
      summary: "Validation blocked: task budget is required.",
      status: "blocked",
      reason: "missing_budget"
    )
  end

  defp validation_feedback(%PromptRequest{} = prompt_request, :insufficient_tokens) do
    base_validation_feedback(prompt_request,
      summary: "Validation blocked: task budget is insufficient.",
      status: "blocked",
      reason: "insufficient_tokens"
    )
  end

  defp validation_feedback(%PromptRequest{} = prompt_request, reason) do
    base_validation_feedback(prompt_request,
      summary: "Validation failed: #{inspect(reason)}",
      status: "failed",
      reason: inspect(reason)
    )
  end

  defp maybe_create_prompt_request_session(_repo, %PromptRequest{} = prompt_request)
       when prompt_request.review_status != :accepted do
    {:ok, prompt_request}
  end

  defp maybe_create_prompt_request_session(
         _repo,
         %PromptRequest{session_id: session_id} = prompt_request
       )
       when is_binary(session_id) do
    {:ok, prompt_request}
  end

  defp maybe_create_prompt_request_session(repo, %PromptRequest{} = prompt_request) do
    attrs = prompt_request_session_attrs(prompt_request)

    with {:ok, session} <- repo.insert(Session.create_changeset(%Session{}, attrs)) do
      prompt_request
      |> Ecto.Changeset.change(%{session_id: session.id})
      |> repo.update()
    end
  end

  defp prompt_request_session_attrs(%PromptRequest{} = prompt_request) do
    %{
      session_id: "prompt-request-#{prompt_request.id}",
      goal: prompt_request.title || "Prompt request #{prompt_request.id}",
      repository_id: prompt_request.repository_id,
      user_id: prompt_request.user_id,
      metadata: %{
        "prompt_request_id" => prompt_request.id,
        "prompt_request" => prompt_request_snapshot(prompt_request)
      }
    }
  end

  defp prompt_request_snapshot(%PromptRequest{} = prompt_request) do
    %{
      "title" => prompt_request.title,
      "prompt" => prompt_request.prompt,
      "system_prompt" => prompt_request.system_prompt,
      "result" => prompt_request.result,
      "conversation" => prompt_request.conversation,
      "origin" => normalize_origin(prompt_request.origin),
      "model" => prompt_request.model,
      "model_version" => prompt_request.model_version,
      "token_count" => prompt_request.token_count,
      "generated_at" => format_datetime(prompt_request.generated_at),
      "review_status" => prompt_request.review_status,
      "reviewed_at" => format_datetime(prompt_request.reviewed_at),
      "validation_feedback" => format_validation_feedback(prompt_request.validation_feedback),
      "validation_iterations" => prompt_request.validation_iterations,
      "execution_environment" => prompt_request.execution_environment,
      "execution_duration_ms" => prompt_request.execution_duration_ms,
      "attestation" => prompt_request.attestation
    }
  end

  defp maybe_filter_registry_search(query, nil), do: query
  defp maybe_filter_registry_search(query, ""), do: query

  defp maybe_filter_registry_search(query, search) when is_binary(search) do
    pattern = "%#{search}%"

    where(
      query,
      [prompt_request],
      ilike(prompt_request.title, ^pattern) or
        ilike(prompt_request.prompt, ^pattern) or
        ilike(prompt_request.system_prompt, ^pattern) or
        ilike(prompt_request.result, ^pattern)
    )
  end

  defp maybe_filter_review_status(query, nil), do: query

  defp maybe_filter_review_status(query, review_status) do
    where(query, [prompt_request], prompt_request.review_status == ^review_status)
  end

  defp maybe_filter_curated(query, true) do
    where(query, [prompt_request], not is_nil(prompt_request.curated_at))
  end

  defp maybe_filter_curated(query, false), do: query

  defp maybe_limit_registry(query, nil), do: query

  defp maybe_limit_registry(query, limit) when is_integer(limit) and limit > 0 do
    limit(query, ^limit)
  end

  defp maybe_limit_registry(query, _limit), do: query

  defp maybe_filter_approved_templates(query, true) do
    where(query, [prompt_template], not is_nil(prompt_template.approved_at))
  end

  defp maybe_filter_approved_templates(query, false), do: query

  defp normalize_origin(origin) when is_atom(origin), do: Atom.to_string(origin)
  defp normalize_origin(origin) when is_binary(origin), do: origin
  defp normalize_origin(_origin), do: nil

  defp format_datetime(nil), do: nil
  defp format_datetime(%DateTime{} = datetime), do: DateTime.to_iso8601(datetime)

  defp validation_iteration_count(%PromptRequest{} = prompt_request) do
    ValidationRun
    |> where([run], run.prompt_request_id == ^prompt_request.id)
    |> Repo.aggregate(:count, :id)
  end

  defp encode_validation_feedback(nil), do: nil

  defp encode_validation_feedback(%{} = feedback) do
    Jason.encode!(feedback)
  end

  defp encode_validation_feedback(feedback) when is_binary(feedback), do: feedback
  defp encode_validation_feedback(feedback), do: Jason.encode!(%{"summary" => inspect(feedback)})

  defp base_validation_feedback(%PromptRequest{} = prompt_request, attrs) do
    summary = Keyword.get(attrs, :summary, "Validation failed.")
    status = Keyword.get(attrs, :status, "failed")
    reason = Keyword.get(attrs, :reason)

    %{
      "summary" => summary,
      "status" => status,
      "iteration" => validation_iteration_count(prompt_request)
    }
    |> maybe_put_value("reason", reason)
  end

  defp quality_score_payload(%ValidationRun{metrics: metrics}) when is_map(metrics) do
    scores = Map.get(metrics, "quality_scores") || Map.get(metrics, :quality_scores)
    overall = Map.get(metrics, "quality_score") || Map.get(metrics, :quality_score)

    threshold_failed =
      Map.get(metrics, "quality_threshold_failed") || Map.get(metrics, :quality_threshold_failed)

    threshold_min =
      Map.get(metrics, "quality_threshold_min") || Map.get(metrics, :quality_threshold_min)

    %{}
    |> maybe_put_value("quality_scores", normalize_score_keys(scores))
    |> maybe_put_value("quality_score", overall)
    |> maybe_put_value(
      "quality_threshold",
      quality_threshold_payload(threshold_failed, threshold_min)
    )
  end

  defp quality_score_payload(_run), do: %{}

  defp validation_summary_for_run(%ValidationRun{metrics: metrics}) when is_map(metrics) do
    threshold_failed =
      Map.get(metrics, "quality_threshold_failed") ||
        Map.get(metrics, :quality_threshold_failed)

    if threshold_failed do
      score = Map.get(metrics, "quality_score") || Map.get(metrics, :quality_score)

      min_score =
        Map.get(metrics, "quality_threshold_min") || Map.get(metrics, :quality_threshold_min)

      "Validation failed: quality score #{format_score(score)}/100 below minimum #{format_score(min_score)}."
    else
      "Validation failed."
    end
  end

  defp validation_summary_for_run(_run), do: "Validation failed."

  defp quality_threshold_payload(nil, nil), do: nil

  defp quality_threshold_payload(failed, min) do
    %{
      "failed" => failed,
      "minimum" => min
    }
  end

  defp failure_payload(%ValidationRun{check_results: %{"checks" => checks}})
       when is_list(checks) do
    failed =
      Enum.filter(checks, fn check ->
        Map.get(check, "exit_code") != 0
      end)

    failures =
      Enum.map(failed, fn check ->
        %{
          "check_id" => Map.get(check, "id"),
          "label" => Map.get(check, "label", "Check"),
          "kind" => Map.get(check, "kind"),
          "exit_code" => Map.get(check, "exit_code"),
          "command" => Map.get(check, "command"),
          "args" => Map.get(check, "args", []),
          "stdout" => truncate_output(Map.get(check, "stdout", ""))
        }
      end)

    if failures == [] do
      %{}
    else
      %{"failures" => failures}
    end
  end

  defp failure_payload(%ValidationRun{
         check_results: %{"error" => %{"stage" => stage, "reason" => reason}}
       }) do
    %{
      "failures" => [
        %{
          "stage" => stage,
          "reason" => reason,
          "message" => "Validation error during #{stage}."
        }
      ]
    }
  end

  defp failure_payload(_run), do: %{}

  defp suggested_fixes_payload(%ValidationRun{check_results: %{"checks" => checks}})
       when is_list(checks) do
    fixes =
      checks
      |> Enum.filter(&(Map.get(&1, "exit_code") != 0))
      |> Enum.map(&suggested_fix_for_check/1)
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq()

    if fixes == [] do
      %{}
    else
      %{"suggested_fixes" => fixes}
    end
  end

  defp suggested_fixes_payload(_run), do: %{}

  defp suggested_fix_for_check(check) do
    check_id = Map.get(check, "id")
    label = Map.get(check, "label", "Check")
    command = Map.get(check, "command")
    args = Map.get(check, "args", [])
    command_string = format_command(command, args)

    case check_id do
      "format" -> "Run #{command_string} and reformat the code."
      "compile" -> "Run #{command_string} and resolve compile errors."
      "test" -> "Run #{command_string} and fix failing tests."
      "e2e" -> "Run #{command_string} and address end-to-end test failures."
      "credo" -> "Run #{command_string} and address lint warnings."
      "dialyzer" -> "Run #{command_string} and resolve type analysis issues."
      "semgrep" -> "Review #{label} output and resolve security findings."
      "sobelow" -> "Review #{label} output and resolve security warnings."
      "performance_baseline" -> "Run #{command_string} and address performance regressions."
      _ -> "Review #{label} output and resolve reported issues."
    end
  end

  defp format_command(nil, _args), do: "the failing check"

  defp format_command(command, args) do
    [command | List.wrap(args)]
    |> Enum.map_join(" ", &to_string/1)
  end

  defp normalize_score_keys(nil), do: nil

  defp normalize_score_keys(scores) when is_map(scores) do
    Map.new(scores, fn {key, value} -> {to_string(key), value} end)
  end

  defp normalize_score_keys(_scores), do: nil

  defp truncate_output(output) when is_binary(output) do
    limit = 1200

    if String.length(output) > limit do
      String.slice(output, 0, limit) <> "...(truncated)"
    else
      output
    end
  end

  defp truncate_output(_output), do: nil

  defp maybe_put_value(map, _key, nil), do: map
  defp maybe_put_value(map, key, value), do: Map.put(map, key, value)

  defp format_score(score) when is_number(score), do: score
  defp format_score(_score), do: "n/a"
end
