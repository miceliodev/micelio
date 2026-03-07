defmodule Micelio.Plans do
  @moduledoc """
  Context for plan contributions.
  """

  import Ecto.Query, warn: false

  alias Ecto.Multi
  alias Micelio.AITokens
  alias Micelio.Authorization
  alias Micelio.ContributionConfidence
  alias Micelio.LLM

  alias Micelio.Plans.{
    ACPEnvelope,
    ACPClient,
    ACPRedactor,
    AgenticACPClient,
    Plan,
    PlanMessage,
    PlanSuggestion,
    PlanTemplate
  }

  alias Micelio.Repo
  alias Micelio.Repositories.Repository
  alias Micelio.Sandboxes
  alias Micelio.Sandboxes.Limits
  alias Micelio.Sessions.Session
  alias Micelio.ValidationEnvironments
  alias Micelio.ValidationEnvironments.ValidationRun
  alias MicelioWeb.Endpoint

  # --- Agentic Session Functions ---

  def start_agentic_session(%Plan{} = plan, opts) do
    user = Keyword.fetch!(opts, :user)
    notify_pid = Keyword.fetch!(opts, :notify_pid)
    account = Keyword.get(opts, :account)
    agent = Keyword.get(opts, :agent, "pi")
    model = Keyword.get(opts, :model) || resolve_model(account)
    provider_name = Keyword.get(opts, :provider, Sandboxes.default_provider())
    llm_provider = resolve_llm_provider(account)
    llm_api_key = resolve_llm_api_key(account)

    AgenticACPClient.stop(plan.id)

    env =
      [
        llm_api_key && {"ANTHROPIC_API_KEY", llm_api_key},
        llm_api_key && {"OPENAI_API_KEY", llm_api_key}
      ]
      |> Enum.reject(&is_nil/1)

    with :ok <- authorize_session_start(plan, user),
         :ok <- Limits.can_start_workspace?(user.id),
         server_url = sandbox_server_url(),
         {:ok, workspace} <-
           Sandboxes.create_workspace(provider_name, plan,
             cwd: File.cwd!(),
             env: env,
             server_url: server_url
           ),
         started_at = DateTime.utc_now() |> DateTime.truncate(:second),
         expires_at =
           DateTime.add(started_at, Limits.max_session_duration_minutes(), :minute)
           |> DateTime.truncate(:second),
         {:ok, updated_plan} <-
           plan
           |> Plan.sandbox_changeset(%{
             sandbox_workspace_id: workspace.workspace_id,
             sandbox_provider: provider_name,
             sandbox_status: "running",
             sandbox_started_at: started_at,
             sandbox_expires_at: expires_at,
             sandbox_metadata: Map.get(workspace, :metadata, %{})
           })
           |> Repo.update(),
         {:ok, _} <- Limits.record_workspace_start(user.id) do
      case AgenticACPClient.start(plan.id,
             notify_pid: notify_pid,
             connection_info: workspace.connection_info,
             agent: agent,
             model: model,
             llm_provider: llm_provider
           ) do
        {:ok, _pid} ->
          {:ok, updated_plan}

        {:error, reason} ->
          Limits.record_workspace_stop(user.id, 0)

          updated_plan
          |> Plan.sandbox_changeset(%{sandbox_status: "error"})
          |> Repo.update()

          {:error, reason}
      end
    end
  end

  defp resolve_model(nil), do: nil

  defp resolve_model(account) do
    LLM.repository_default_model_for_account(account)
  end

  defp resolve_llm_provider(nil), do: nil
  defp resolve_llm_provider(%{llm_provider: p}) when is_binary(p) and p != "", do: p
  defp resolve_llm_provider(_), do: nil

  defp resolve_llm_api_key(nil), do: nil
  defp resolve_llm_api_key(%{llm_api_key_encrypted: k}) when is_binary(k) and k != "", do: k
  defp resolve_llm_api_key(_), do: nil

  defp sandbox_server_url do
    config = Application.get_env(:micelio, Micelio.Sandboxes, [])

    case Keyword.get(config, :module_server_url) do
      url when is_binary(url) and url != "" ->
        String.trim_trailing(url, "/")

      _ ->
        MicelioWeb.Endpoint.url()
    end
  end

  defp authorize_session_start(%Plan{} = plan, user) do
    case Repo.preload(plan, :repository) do
      %{repository: %Repository{} = repository} ->
        Authorization.authorize(:repository_write, user, repository)

      _ ->
        {:error, :forbidden}
    end
  end

  def stop_agentic_session(%Plan{} = plan) do
    AgenticACPClient.stop(plan.id)

    if plan.sandbox_provider && plan.sandbox_workspace_id do
      Sandboxes.destroy_workspace(plan.sandbox_provider, plan.sandbox_workspace_id)
    end

    duration_minutes =
      if plan.sandbox_started_at do
        DateTime.diff(DateTime.utc_now(), plan.sandbox_started_at, :second)
        |> div(60)
        |> max(1)
      else
        0
      end

    Limits.record_workspace_stop(plan.user_id, duration_minutes)

    plan
    |> Plan.sandbox_changeset(%{sandbox_status: "stopped"})
    |> Repo.update()
  end

  def reconnect_agentic_session(%Plan{} = plan, opts) do
    notify_pid = Keyword.fetch!(opts, :notify_pid)

    if AgenticACPClient.running?(plan.id) do
      AgenticACPClient.update_notify_pid(plan.id, notify_pid)
    else
      {:error, :not_running}
    end
  end

  def reset_stale_sandbox(%Plan{} = plan) do
    if plan.sandbox_status in ["running", "provisioning"] do
      Limits.reset_active_workspaces(plan.user_id)
    end

    plan
    |> Plan.sandbox_changeset(%{sandbox_status: "stopped"})
    |> Repo.update()
  end

  def send_agentic_message(%Plan{} = plan, content) do
    AgenticACPClient.prompt(plan.id, content)
  end

  def finalize_plan_streaming_messages(plan_id) do
    plan_id_val = if is_struct(plan_id), do: plan_id.id, else: plan_id

    {_count, messages} =
      PlanMessage
      |> where([m], m.plan_id == ^plan_id_val and m.status == "streaming")
      |> Repo.update_all([set: [status: "complete"]], returning: true)

    messages
  end

  # --- Agent Functions ---

  def start_agent_for_plan(%Plan{} = plan, opts) do
    notify_pid = Keyword.fetch!(opts, :notify_pid)
    agent = Keyword.get(opts, :agent, "claude")
    model = Keyword.get(opts, :model, "sonnet")

    case ACPClient.start(plan.id,
           notify_pid: notify_pid,
           agent: agent,
           model: model
         ) do
      {:ok, pid} ->
        plan
        |> Ecto.Changeset.change(%{agent: agent, agent_model: model, agent_status: "connected"})
        |> Repo.update()

        {:ok, pid}

      {:error, reason} ->
        {:error, reason}
    end
  end

  def send_agent_message(%Plan{} = plan, content) do
    ACPClient.prompt(plan.id, content)
  end

  def stop_agent_for_plan(%Plan{} = plan) do
    ACPClient.stop(plan.id)

    plan
    |> Ecto.Changeset.change(%{agent_status: "idle"})
    |> Repo.update()
  end

  def update_plan_title(%Plan{} = plan, title) when is_binary(title) do
    plan
    |> Ecto.Changeset.change(%{title: title})
    |> Repo.update()
  end

  def create_plan_message(plan_id, attrs) when is_binary(plan_id) do
    %PlanMessage{}
    |> PlanMessage.changeset(Map.put(attrs, :plan_id, plan_id))
    |> Repo.insert()
  end

  def create_plan_message(%Plan{} = plan, attrs) do
    create_plan_message(plan.id, attrs)
  end

  def update_plan_message(%PlanMessage{} = message, attrs) do
    message
    |> PlanMessage.changeset(attrs)
    |> Repo.update()
  end

  def persist_acp_envelope(%Plan{} = plan, attrs) when is_map(attrs) do
    persist_acp_envelope(plan.id, attrs)
  end

  def persist_acp_envelope(plan_id, attrs) when is_binary(plan_id) and is_map(attrs) do
    payload = attrs |> Map.get(:payload) || Map.get(attrs, "payload") || %{}
    direction = attrs |> Map.get(:direction) || Map.get(attrs, "direction") || "update"
    event_type = attrs |> Map.get(:event_type) || Map.get(attrs, "event_type") || "unknown"

    %ACPEnvelope{}
    |> ACPEnvelope.changeset(%{
      plan_id: plan_id,
      direction: to_string(direction),
      event_type: to_string(event_type),
      payload: normalize_acp_payload(payload),
      sequence: next_acp_sequence(plan_id)
    })
    |> Repo.insert()
  rescue
    _ -> {:error, :acp_envelope_persist_failed}
  end

  def list_acp_envelopes(%Plan{} = plan, opts \\ []) do
    limit = Keyword.get(opts, :limit, 200)

    ACPEnvelope
    |> where([e], e.plan_id == ^plan.id)
    |> order_by([e], asc: e.sequence)
    |> limit(^limit)
    |> Repo.all()
  end

  def list_plan_messages(%Plan{} = plan) do
    PlanMessage
    |> where([m], m.plan_id == ^plan.id and m.role != "comment")
    |> order_by([m], asc: m.sequence, asc: m.inserted_at)
    |> Repo.all()
  end

  def list_plan_comments(%Plan{} = plan) do
    PlanMessage
    |> where([m], m.plan_id == ^plan.id and m.role == "comment")
    |> order_by([m], asc: m.inserted_at)
    |> Repo.all()
  end

  def add_plan_comment(%Plan{} = plan, user, attrs) do
    content =
      attrs
      |> comment_content()
      |> String.trim()

    if content == "" do
      {:error, :empty_comment}
    else
      create_plan_message(plan, %{
        role: "comment",
        content: content,
        author: comment_author(user),
        status: "complete",
        sequence: next_message_sequence(plan)
      })
    end
  end

  def next_message_sequence(%Plan{} = plan) do
    current_max =
      PlanMessage
      |> where([m], m.plan_id == ^plan.id)
      |> select([m], max(m.sequence))
      |> Repo.one()

    (current_max || 0) + 1
  end

  defp comment_content(%{"content" => content}) when is_binary(content), do: content
  defp comment_content(%{content: content}) when is_binary(content), do: content
  defp comment_content(_), do: ""

  defp comment_author(%{email: email}) when is_binary(email) and email != "", do: email
  defp comment_author(_), do: "unknown"

  defp next_acp_sequence(plan_id) do
    current_max =
      ACPEnvelope
      |> where([e], e.plan_id == ^plan_id)
      |> select([e], max(e.sequence))
      |> Repo.one()

    (current_max || 0) + 1
  end

  defp normalize_acp_payload(payload) do
    payload
    |> to_json_safe()
    |> ACPRedactor.redact()
    |> normalize_map_payload()
  end

  defp normalize_map_payload(%{} = payload), do: payload
  defp normalize_map_payload(payload), do: %{"value" => payload}

  defp to_json_safe(value) when is_binary(value) or is_number(value) or is_boolean(value),
    do: value

  defp to_json_safe(nil), do: nil

  defp to_json_safe(%DateTime{} = datetime), do: DateTime.to_iso8601(datetime)
  defp to_json_safe(%NaiveDateTime{} = datetime), do: NaiveDateTime.to_iso8601(datetime)

  defp to_json_safe(%_{} = struct) do
    struct
    |> Map.from_struct()
    |> Map.delete(:__meta__)
    |> to_json_safe()
  end

  defp to_json_safe(value) when is_map(value) do
    Enum.reduce(value, %{}, fn {key, nested}, acc ->
      Map.put(acc, to_json_key(key), to_json_safe(nested))
    end)
  end

  defp to_json_safe(value) when is_list(value), do: Enum.map(value, &to_json_safe/1)
  defp to_json_safe(value) when is_atom(value), do: Atom.to_string(value)

  defp to_json_safe(value) when is_tuple(value) do
    value
    |> Tuple.to_list()
    |> Enum.map(&to_json_safe/1)
  end

  defp to_json_safe(value) when is_pid(value) or is_port(value) or is_reference(value) do
    inspect(value)
  end

  defp to_json_safe(value), do: inspect(value)

  defp to_json_key(key) when is_binary(key), do: key
  defp to_json_key(key) when is_atom(key), do: Atom.to_string(key)
  defp to_json_key(key), do: inspect(key)

  # --- Plan CRUD Functions ---

  def confidence_score(%Plan{} = plan, opts \\ []) do
    ContributionConfidence.score_for_plan(plan, opts)
  end

  def confidence_scores(plans, opts \\ []) when is_list(plans) do
    ContributionConfidence.scores_for_plans(plans, opts)
  end

  def list_plans_for_repository(repository, opts \\ []) do
    status = Keyword.get(opts, :status, "open")

    Plan
    |> where([plan], plan.repository_id == ^repository.id)
    |> maybe_filter_plan_status(status)
    |> order_by([plan], desc: plan.number, desc: plan.inserted_at)
    |> preload(:user)
    |> Repo.all()
  end

  def count_plans_by_status(repository) do
    Plan
    |> where([plan], plan.repository_id == ^repository.id)
    |> group_by([plan], plan.status)
    |> select([plan], {plan.status, count(plan.id)})
    |> Repo.all()
    |> Map.new()
  end

  defp maybe_filter_plan_status(query, nil), do: query
  defp maybe_filter_plan_status(query, status), do: where(query, [plan], plan.status == ^status)

  def list_plan_registry(opts \\ []) do
    search = Keyword.get(opts, :search)
    review_status = Keyword.get(opts, :review_status)
    curated_only = Keyword.get(opts, :curated_only, false)
    limit = Keyword.get(opts, :limit)

    Plan
    |> order_by([plan], desc: plan.inserted_at)
    |> maybe_filter_registry_search(search)
    |> maybe_filter_review_status(review_status)
    |> maybe_filter_curated(curated_only)
    |> maybe_limit_registry(limit)
    |> preload([:user, :plan_template, :curated_by, repository: [organization: :account]])
    |> Repo.all()
  end

  def count_plans_for_repository(repository) do
    Plan
    |> where([plan], plan.repository_id == ^repository.id)
    |> select([plan], count(plan.id))
    |> Repo.one()
  end

  def get_plan_for_repository(repository, id) do
    Plan
    |> where(
      [plan],
      plan.repository_id == ^repository.id and plan.id == ^id
    )
    |> preload([:user, :parent_plan, :plan_template, :curated_by, suggestions: :user])
    |> Repo.one()
  end

  def get_plan_by_number(repository, number) do
    Plan
    |> where(
      [plan],
      plan.repository_id == ^repository.id and plan.number == ^number
    )
    |> preload(:user)
    |> Repo.one()
  end

  def create_simple_plan(attrs, opts) do
    repository = fetch_repository_opt!(opts)
    user = Keyword.fetch!(opts, :user)
    conversation = Keyword.get(opts, :conversation, %{})
    normalized_conversation = normalize_plan_conversation(conversation)

    Repo.transaction(fn ->
      number = next_number_for_repository(repository)

      result =
        %Plan{}
        |> Plan.simple_changeset(attrs)
        |> Ecto.Changeset.put_change(:repository_id, repository.id)
        |> Ecto.Changeset.put_change(:user_id, user.id)
        |> Ecto.Changeset.put_change(:number, number)
        |> Ecto.Changeset.put_change(:origin, :human)
        |> Ecto.Changeset.put_change(:conversation, normalized_conversation)
        |> Repo.insert()

      case result do
        {:ok, plan} -> plan
        {:error, changeset} -> Repo.rollback(changeset)
      end
    end)
  end

  defp next_number_for_repository(repository) do
    # Use advisory lock to prevent race conditions on number assignment
    lock_key = :erlang.phash2({"plan_number", repository.id})
    Repo.query!("SELECT pg_advisory_xact_lock($1)", [lock_key])

    current_max =
      Plan
      |> where([pr], pr.repository_id == ^repository.id)
      |> select([pr], max(pr.number))
      |> Repo.one()

    (current_max || 0) + 1
  end

  def change_plan(%Plan{} = plan, attrs \\ %{}) do
    Plan.changeset(plan, attrs)
  end

  def change_simple_plan(%Plan{} = plan, attrs \\ %{}) do
    Plan.simple_changeset(plan, attrs)
  end

  def update_plan(%Plan{} = plan, attrs) do
    plan
    |> Plan.simple_changeset(attrs)
    |> Repo.update()
  end

  def close_plan(%Plan{} = plan) do
    plan
    |> Plan.status_changeset("closed")
    |> Repo.update()
  end

  def reopen_plan(%Plan{} = plan) do
    plan
    |> Plan.status_changeset("open")
    |> Repo.update()
  end

  def curate_plan(%Plan{} = plan, curator) do
    attrs = %{
      curated_at: DateTime.utc_now() |> DateTime.truncate(:second),
      curated_by_id: curator.id
    }

    plan
    |> Plan.curation_changeset(attrs)
    |> Repo.update()
  end

  def list_plan_templates(opts \\ []) do
    only_approved = Keyword.get(opts, :only_approved, false)

    PlanTemplate
    |> order_by([pt], asc: pt.name)
    |> maybe_filter_approved_templates(only_approved)
    |> Repo.all()
  end

  def get_plan_template(id) do
    Repo.get(PlanTemplate, id)
  end

  def change_plan_template(%PlanTemplate{} = plan_template, attrs \\ %{}) do
    PlanTemplate.changeset(plan_template, attrs)
  end

  def create_plan_template(attrs, opts) do
    created_by = Keyword.fetch!(opts, :created_by)

    %PlanTemplate{}
    |> PlanTemplate.changeset(attrs)
    |> Ecto.Changeset.put_change(:created_by_id, created_by.id)
    |> Repo.insert()
  end

  def approve_plan_template(%PlanTemplate{} = plan_template, approver) do
    attrs = %{
      approved_at: DateTime.utc_now() |> DateTime.truncate(:second),
      approved_by_id: approver.id
    }

    plan_template
    |> PlanTemplate.approval_changeset(attrs)
    |> Repo.update()
  end

  def create_plan(attrs, opts) do
    repository = fetch_repository_opt!(opts)
    user = Keyword.fetch!(opts, :user)

    %Plan{}
    |> Plan.changeset(attrs)
    |> Ecto.Changeset.put_change(:repository_id, repository.id)
    |> Ecto.Changeset.put_change(:user_id, user.id)
    |> ensure_generation_depth(max_generation_depth(opts))
    |> put_attestation()
    |> Repo.insert()
  end

  def add_planning_entry(%Plan{} = plan, attrs) do
    with {:ok, entry} <- normalize_planning_entry(attrs) do
      conversation = normalize_plan_conversation(plan.conversation)
      messages = normalize_planning_messages(Map.get(conversation, "messages", []))

      updated_conversation =
        conversation
        |> Map.put("messages", messages ++ [entry])
        |> maybe_set_plan(entry)

      plan
      |> Ecto.Changeset.change(conversation: updated_conversation)
      |> Repo.update()
    end
  end

  defp normalize_plan_conversation(nil), do: %{"messages" => []}

  defp normalize_plan_conversation(conversation) when is_map(conversation) do
    conversation
    |> map_to_string_keys()
    |> Map.put_new("messages", [])
  end

  defp normalize_plan_conversation(_), do: %{"messages" => []}

  defp map_to_string_keys(value) when is_map(value) do
    Enum.reduce(value, %{}, fn
      {key, value}, acc when is_atom(key) -> Map.put(acc, to_string(key), value)
      {key, value}, acc -> Map.put(acc, key, value)
    end)
  end

  defp map_to_string_keys(_), do: %{}

  defp normalize_planning_messages(messages) when is_list(messages) do
    Enum.reduce(messages, [], fn
      message, acc when is_map(message) ->
        normalized =
          message
          |> map_to_string_keys()
          |> normalize_stored_planning_message()

        if normalized == nil, do: acc, else: acc ++ [normalized]

      _, acc ->
        acc
    end)
  end

  defp normalize_planning_messages(_), do: []

  defp normalize_stored_planning_message(message) do
    role = normalize_planning_role(Map.get(message, "role") || Map.get(message, :role))

    content =
      normalize_planning_content(Map.get(message, "content") || Map.get(message, :content))

    if content != nil do
      base = %{"role" => role, "content" => content, "created_at" => DateTime.utc_now()}

      model = normalize_planning_model(Map.get(message, "model") || Map.get(message, :model))
      author = normalize_planning_author(Map.get(message, "author") || Map.get(message, :author))

      [
        {"model", model},
        {"author", author}
      ]
      |> Enum.reduce(base, fn {key, value}, acc ->
        if value == nil, do: acc, else: Map.put(acc, key, value)
      end)
    end
  end

  defp normalize_planning_entry(attrs) when is_map(attrs) do
    role = normalize_planning_role(Map.get(attrs, "role") || Map.get(attrs, :role))
    content = normalize_planning_content(Map.get(attrs, "content") || Map.get(attrs, :content))

    if content == nil do
      {:error, :conversation_content_required}
    else
      model = normalize_planning_model(Map.get(attrs, "model") || Map.get(attrs, :model))
      author = normalize_planning_author(Map.get(attrs, :author) || Map.get(attrs, "author"))

      entry =
        %{
          "role" => role,
          "content" => content,
          "created_at" => DateTime.utc_now() |> DateTime.to_iso8601()
        }

      entry = if model, do: Map.put(entry, "model", model), else: entry
      entry = if author, do: Map.put(entry, "author", author), else: entry

      {:ok, entry}
    end
  end

  defp normalize_planning_entry(_), do: {:error, :conversation_content_required}

  defp normalize_planning_role("assistant"), do: "assistant"
  defp normalize_planning_role("plan"), do: "plan"
  defp normalize_planning_role(_), do: "human"

  defp normalize_planning_content(nil), do: nil

  defp normalize_planning_content(value) when is_binary(value) do
    value
    |> String.trim()
    |> case do
      "" -> nil
      content -> content
    end
  end

  defp normalize_planning_content(_), do: nil

  defp normalize_planning_model(nil), do: nil

  defp normalize_planning_model(value) when is_binary(value) do
    value
    |> String.trim()
    |> case do
      "" -> nil
      model -> model
    end
  end

  defp normalize_planning_model(_), do: nil

  defp normalize_planning_author(nil), do: nil

  defp normalize_planning_author(value) when is_binary(value) do
    value
    |> String.trim()
    |> case do
      "" -> nil
      author -> author
    end
  end

  defp normalize_planning_author(_), do: nil

  defp maybe_set_plan(conversation, %{"role" => "plan", "content" => content}) do
    Map.put(conversation, "plan", content)
  end

  defp maybe_set_plan(conversation, _), do: conversation

  defp fetch_repository_opt!(opts) do
    case Keyword.fetch(opts, :repository) do
      {:ok, repository} ->
        repository

      :error ->
        Keyword.fetch!(opts, :project)
    end
  end

  def submit_plan(attrs, opts) do
    repository = fetch_repository_opt!(opts)
    user = Keyword.fetch!(opts, :user)

    flow_opts =
      Keyword.get(opts, :flow_opts, Application.get_env(:micelio, :plan_flow, []))

    validation_enabled =
      Keyword.get(opts, :validation_enabled, Keyword.get(flow_opts, :validation_enabled, true))

    validation_async =
      Keyword.get(opts, :validation_async, Keyword.get(flow_opts, :validation_async, true))

    validation_opts =
      Keyword.get(opts, :validation_opts, Keyword.get(flow_opts, :validation_opts, []))

    task_budget_amount =
      Keyword.get(opts, :task_budget_amount, Keyword.get(flow_opts, :task_budget_amount))

    with {:ok, plan} <-
           create_plan(attrs, repository: repository, user: user),
         :ok <- maybe_allocate_task_budget(plan, task_budget_amount) do
      cond do
        validation_enabled and validation_async ->
          run_plan_validation(plan, validation_opts, true)
          {:ok, plan}

        validation_enabled ->
          finalize_plan_validation(plan, validation_opts)

        true ->
          {:ok, plan}
      end
    end
  end

  def list_plan_suggestions(%Plan{} = plan) do
    PlanSuggestion
    |> where([ps], ps.plan_id == ^plan.id)
    |> order_by([ps], asc: ps.inserted_at)
    |> preload(:user)
    |> Repo.all()
  end

  def change_plan_suggestion(%PlanSuggestion{} = plan_suggestion, attrs \\ %{}) do
    PlanSuggestion.changeset(plan_suggestion, attrs)
  end

  def create_plan_suggestion(%Plan{} = plan, attrs, opts) do
    user = Keyword.fetch!(opts, :user)

    Multi.new()
    |> Multi.insert(
      :plan_suggestion,
      %PlanSuggestion{}
      |> PlanSuggestion.changeset(attrs)
      |> Ecto.Changeset.put_change(:plan_id, plan.id)
      |> Ecto.Changeset.put_change(:user_id, user.id)
    )
    |> Multi.run(:token_earning, fn repo, %{plan_suggestion: suggestion} ->
      AITokens.ensure_plan_suggestion_earning(repo, suggestion, plan)
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{plan_suggestion: suggestion}} ->
        {:ok, suggestion}

      {:error, :plan_suggestion, %Ecto.Changeset{} = changeset, _changes} ->
        {:error, changeset}

      {:error, :token_earning, %Ecto.Changeset{} = changeset, _changes} ->
        {:error, changeset}
    end
  end

  def list_validation_runs(%Plan{} = plan) do
    ValidationEnvironments.list_runs_for_plan(plan)
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

  def run_validation(%Plan{} = plan, opts \\ []) do
    config_opts = Application.get_env(:micelio, :validation_environments, [])

    ValidationEnvironments.run_for_plan(
      plan,
      Keyword.merge(config_opts, opts)
    )
  end

  def run_validation_async(%Plan{} = plan, notify_pid, opts \\ []) do
    Task.Supervisor.start_child(Micelio.ValidationEnvironments.Supervisor, fn ->
      finalize_plan_validation(
        plan,
        Keyword.put(opts, :notify_pid, notify_pid)
      )
    end)
  end

  def review_plan(%Plan{} = plan, reviewer, status)
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

    should_award? = status == :accepted and plan.review_status != :accepted

    Multi.new()
    |> Multi.update(:plan, Plan.review_changeset(plan, attrs))
    |> Multi.run(:plan_session, fn repo, %{plan: updated} ->
      maybe_create_plan_session(repo, updated)
    end)
    |> maybe_award_plan_earning(should_award?)
    |> Repo.transaction()
    |> case do
      {:ok, %{plan_session: updated}} ->
        {:ok, updated}

      {:error, :plan, %Ecto.Changeset{} = changeset, _changes} ->
        {:error, changeset}

      {:error, :plan_session, reason, _changes} ->
        {:error, reason}

      {:error, :token_earning, reason, _changes} ->
        {:error, reason}
    end
  end

  def attestation_status(%Plan{} = plan) do
    case plan.attestation do
      %{"signature" => signature} when is_binary(signature) ->
        if signature == sign_attestation(Plan.attestation_payload(plan)) do
          :verified
        else
          :invalid
        end

      _ ->
        :missing
    end
  end

  def lineage(%Plan{} = plan, opts \\ []) do
    max_depth = Keyword.get(opts, :max_depth, 5)
    build_lineage(plan.parent_plan_id, max_depth, [])
  end

  defp put_attestation(%Ecto.Changeset{valid?: true} = changeset) do
    payload = Plan.attestation_payload(Ecto.Changeset.apply_changes(changeset))

    attestation = %{
      "signature" => sign_attestation(payload),
      "payload" => payload,
      "signed_at" => DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601()
    }

    Ecto.Changeset.put_change(changeset, :attestation, attestation)
  end

  defp put_attestation(changeset), do: changeset

  defp maybe_award_plan_earning(%Multi{} = multi, true) do
    Multi.run(multi, :token_earning, fn repo, %{plan: plan} ->
      AITokens.ensure_plan_earning(repo, plan)
    end)
  end

  defp maybe_award_plan_earning(%Multi{} = multi, false), do: multi

  defp maybe_allocate_task_budget(_plan, nil), do: :ok

  defp maybe_allocate_task_budget(%Plan{} = plan, amount) do
    case AITokens.upsert_task_budget(plan, %{"amount" => amount}) do
      {:ok, _budget, _pool} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp max_generation_depth(opts) do
    Keyword.get(opts, :max_generation_depth, plan_max_generation_depth())
  end

  defp plan_max_generation_depth do
    :micelio
    |> Application.get_env(:plans, [])
    |> Keyword.get(:max_generation_depth, 3)
  end

  defp ensure_generation_depth(%Ecto.Changeset{} = changeset, max_depth)
       when is_integer(max_depth) and max_depth > 0 do
    parent_id = Ecto.Changeset.get_field(changeset, :parent_plan_id)

    case parent_id do
      nil ->
        changeset

      parent_id ->
        parent_depth = plan_depth(parent_id)

        if parent_depth + 1 > max_depth do
          Ecto.Changeset.add_error(
            changeset,
            :parent_plan_id,
            "exceeds max generation depth"
          )
        else
          changeset
        end
    end
  end

  defp ensure_generation_depth(%Ecto.Changeset{} = changeset, _max_depth), do: changeset

  defp plan_depth(parent_id) do
    plan_depth(parent_id, 0)
  end

  defp plan_depth(nil, depth), do: depth

  defp plan_depth(parent_id, depth) do
    case Repo.get(Plan, parent_id) do
      nil -> depth
      parent -> plan_depth(parent.parent_plan_id, depth + 1)
    end
  end

  defp build_lineage(nil, _depth, acc), do: acc
  defp build_lineage(_parent_id, 0, acc), do: acc

  defp build_lineage(parent_id, depth, acc) do
    case Repo.get(Plan, parent_id) do
      nil ->
        acc

      parent ->
        build_lineage(parent.parent_plan_id, depth - 1, [parent | acc])
    end
  end

  defp sign_attestation(payload) do
    secret = Endpoint.config(:secret_key_base) || raise "secret_key_base is required"
    data = Jason.encode!(payload)
    :crypto.mac(:hmac, :sha256, secret, data) |> Base.encode16(case: :lower)
  end

  defp run_plan_validation(%Plan{} = plan, validation_opts, true) do
    Task.Supervisor.start_child(Micelio.ValidationEnvironments.Supervisor, fn ->
      finalize_plan_validation(plan, validation_opts)
    end)

    :ok
  end

  defp finalize_plan_validation(%Plan{} = plan, validation_opts) do
    case run_validation(plan, validation_opts) do
      {:ok, run} ->
        plan = Repo.preload(plan, :user)

        confidence_score =
          ContributionConfidence.score_for_plan(plan, validation_run: run)

        if ContributionConfidence.auto_accept?(confidence_score) do
          accept_plan(plan, validation_iteration_count(plan))
        else
          update_validation_state(plan, nil, validation_iteration_count(plan))
        end

      {:error, %ValidationRun{} = run} ->
        feedback = validation_feedback(plan, run)
        fail_plan_validation(plan, feedback, reject?: true)

      {:error, reason} ->
        feedback = validation_feedback(plan, reason)
        fail_plan_validation(plan, feedback)
    end
  end

  defp accept_plan(%Plan{} = plan, iterations) do
    plan = Repo.get(Plan, plan.id) || plan

    case review_plan(plan, nil, :accepted) do
      {:ok, updated} ->
        update_validation_state(updated, nil, iterations)

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp update_validation_state(%Plan{} = plan, feedback, iterations) do
    attrs = %{
      validation_feedback: encode_validation_feedback(feedback),
      validation_iterations: iterations
    }

    plan
    |> Ecto.Changeset.change(attrs)
    |> Repo.update()
  end

  defp fail_plan_validation(%Plan{} = plan, feedback, opts \\ []) do
    plan = Repo.get(Plan, plan.id) || plan
    reject? = Keyword.get(opts, :reject?, false)

    plan =
      if reject? do
        case maybe_reject_plan(plan) do
          {:ok, updated} -> updated
          {:error, _reason} -> plan
        end
      else
        plan
      end

    case update_validation_state(
           plan,
           feedback,
           validation_iteration_count(plan)
         ) do
      {:ok, updated} -> {:error, {:validation_failed, feedback, updated}}
      {:error, _changeset} -> {:error, {:validation_failed, feedback, plan}}
    end
  end

  defp maybe_reject_plan(%Plan{review_status: :accepted} = plan), do: {:ok, plan}

  defp maybe_reject_plan(%Plan{review_status: :rejected} = plan), do: {:ok, plan}

  defp maybe_reject_plan(%Plan{} = plan) do
    review_plan(plan, nil, :rejected)
  end

  defp validation_feedback(%Plan{} = plan, %ValidationRun{} = run) do
    summary = validation_summary_for_run(run)

    base =
      base_validation_feedback(plan,
        summary: summary,
        status: "failed"
      )

    base
    |> Map.merge(quality_score_payload(run))
    |> Map.merge(failure_payload(run))
    |> Map.merge(suggested_fixes_payload(run))
    |> Map.put("validation_run_id", run.id)
  end

  defp validation_feedback(%Plan{} = plan, :missing_budget) do
    base_validation_feedback(plan,
      summary: "Validation blocked: task budget is required.",
      status: "blocked",
      reason: "missing_budget"
    )
  end

  defp validation_feedback(%Plan{} = plan, :insufficient_tokens) do
    base_validation_feedback(plan,
      summary: "Validation blocked: task budget is insufficient.",
      status: "blocked",
      reason: "insufficient_tokens"
    )
  end

  defp validation_feedback(%Plan{} = plan, reason) do
    base_validation_feedback(plan,
      summary: "Validation failed: #{inspect(reason)}",
      status: "failed",
      reason: inspect(reason)
    )
  end

  defp maybe_create_plan_session(_repo, %Plan{} = plan) when plan.review_status != :accepted do
    {:ok, plan}
  end

  defp maybe_create_plan_session(_repo, %Plan{session_id: session_id} = plan)
       when is_binary(session_id) do
    {:ok, plan}
  end

  defp maybe_create_plan_session(repo, %Plan{} = plan) do
    attrs = plan_session_attrs(plan)

    with {:ok, session} <- repo.insert(Session.create_changeset(%Session{}, attrs)) do
      plan
      |> Ecto.Changeset.change(%{session_id: session.id})
      |> repo.update()
    end
  end

  defp plan_session_attrs(%Plan{} = plan) do
    %{
      session_id: "plan-#{plan.id}",
      goal: plan.title || "Plan #{plan.id}",
      repository_id: plan.repository_id,
      user_id: plan.user_id,
      metadata: %{
        "plan_id" => plan.id,
        "plan" => plan_snapshot(plan)
      }
    }
  end

  defp plan_snapshot(%Plan{} = plan) do
    %{
      "title" => plan.title,
      "prompt" => plan.prompt,
      "system_prompt" => plan.system_prompt,
      "result" => plan.result,
      "conversation" => plan.conversation,
      "origin" => normalize_origin(plan.origin),
      "model" => plan.model,
      "model_version" => plan.model_version,
      "token_count" => plan.token_count,
      "generated_at" => format_datetime(plan.generated_at),
      "review_status" => plan.review_status,
      "reviewed_at" => format_datetime(plan.reviewed_at),
      "validation_feedback" => format_validation_feedback(plan.validation_feedback),
      "validation_iterations" => plan.validation_iterations,
      "execution_environment" => plan.execution_environment,
      "execution_duration_ms" => plan.execution_duration_ms,
      "attestation" => plan.attestation
    }
  end

  defp maybe_filter_registry_search(query, nil), do: query
  defp maybe_filter_registry_search(query, ""), do: query

  defp maybe_filter_registry_search(query, search) when is_binary(search) do
    pattern = "%#{search}%"

    where(
      query,
      [p],
      ilike(p.title, ^pattern) or
        ilike(p.prompt, ^pattern) or
        ilike(p.system_prompt, ^pattern) or
        ilike(p.result, ^pattern)
    )
  end

  defp maybe_filter_review_status(query, nil), do: query

  defp maybe_filter_review_status(query, review_status) do
    where(query, [p], p.review_status == ^review_status)
  end

  defp maybe_filter_curated(query, true) do
    where(query, [p], not is_nil(p.curated_at))
  end

  defp maybe_filter_curated(query, false), do: query

  defp maybe_limit_registry(query, nil), do: query

  defp maybe_limit_registry(query, limit) when is_integer(limit) and limit > 0 do
    limit(query, ^limit)
  end

  defp maybe_limit_registry(query, _limit), do: query

  defp maybe_filter_approved_templates(query, true) do
    where(query, [pt], not is_nil(pt.approved_at))
  end

  defp maybe_filter_approved_templates(query, false), do: query

  defp normalize_origin(origin) when is_atom(origin), do: Atom.to_string(origin)
  defp normalize_origin(origin) when is_binary(origin), do: origin
  defp normalize_origin(_origin), do: nil

  defp format_datetime(nil), do: nil
  defp format_datetime(%DateTime{} = datetime), do: DateTime.to_iso8601(datetime)

  defp validation_iteration_count(%Plan{} = plan) do
    ValidationRun
    |> where([run], run.plan_id == ^plan.id)
    |> Repo.aggregate(:count, :id)
  end

  defp encode_validation_feedback(nil), do: nil

  defp encode_validation_feedback(%{} = feedback) do
    Jason.encode!(feedback)
  end

  defp encode_validation_feedback(feedback) when is_binary(feedback), do: feedback
  defp encode_validation_feedback(feedback), do: Jason.encode!(%{"summary" => inspect(feedback)})

  defp base_validation_feedback(%Plan{} = plan, attrs) do
    summary = Keyword.get(attrs, :summary, "Validation failed.")
    status = Keyword.get(attrs, :status, "failed")
    reason = Keyword.get(attrs, :reason)

    %{
      "summary" => summary,
      "status" => status,
      "iteration" => validation_iteration_count(plan)
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
