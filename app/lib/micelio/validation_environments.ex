defmodule Micelio.ValidationEnvironments do
  @moduledoc """
  Orchestrates ephemeral validation environments for contributions.
  """

  import Ecto.Query, warn: false

  alias Micelio.AgentInfra
  alias Micelio.AITokens
  alias Micelio.Plans.Plan
  alias Micelio.Repo
  alias Micelio.ValidationEnvironments.{Checks, LocalExecutor, ValidationRun}

  @default_image "micelio/validation-runner:latest"

  def list_runs_for_plan(%Plan{} = plan) do
    ValidationRun
    |> where([run], run.plan_id == ^plan.id)
    |> order_by([run], desc: run.inserted_at)
    |> Repo.all()
  end

  def create_run(%Plan{} = plan, attrs \\ %{}) do
    attrs = Map.put(attrs, :plan_id, plan.id)

    %ValidationRun{}
    |> ValidationRun.changeset(attrs)
    |> Repo.insert()
  end

  def run_for_plan(%Plan{} = plan, opts \\ []) do
    executor = Keyword.get(opts, :executor, LocalExecutor)
    checks = Keyword.get(opts, :checks, Checks.default_checks())
    plan_attrs = plan_attrs(Keyword.get(opts, :plan_attrs, %{}), opts)
    provider_id = Map.get(plan_attrs, :provider) || Map.get(plan_attrs, "provider")
    notify_pid = Keyword.get(opts, :notify_pid)

    result =
      with :ok <- AITokens.ensure_budget_for_plan(plan),
           {:ok, run} <- create_run(plan, %{status: :pending}),
           :ok <- notify(notify_pid, {:validation_started, run}) do
        run_with_environment(run, provider_id, executor, checks, plan_attrs, opts)
      end

    notify(notify_pid, {:validation_finished, plan.id, result})

    result
  end

  defp execute_checks(run, provider_module, instance_ref, executor, checks, opts) do
    started_at = DateTime.utc_now() |> DateTime.truncate(:second)
    started_ms = System.monotonic_time(:millisecond)

    result =
      Checks.run(checks, executor, instance_ref, min_coverage_delta: opts[:min_coverage_delta])
      |> add_quality_scores(checks)
      |> enforce_quality_threshold(opts[:min_quality_score])

    duration_ms = System.monotonic_time(:millisecond) - started_ms

    safe_terminate(provider_module, instance_ref, opts)

    persist_results(run, started_at, duration_ms, result)
  end

  defp run_with_environment(run, provider_id, executor, checks, plan_attrs, opts) do
    initial_state = %{
      run: run,
      provider_id: provider_id,
      provider_module: nil,
      instance_ref: nil,
      request: nil
    }

    with {:ok, state} <- build_request_state(initial_state, plan_attrs),
         {:ok, state} <- resolve_provider_state(state, opts),
         {:ok, state} <- validate_request_state(state, opts),
         {:ok, state} <- provision_state(state, opts),
         {:ok, state} <- mark_running_state(state) do
      execute_checks(state.run, state.provider_module, state.instance_ref, executor, checks, opts)
    else
      {:error, {stage, reason, state}} -> fail_run(state, stage, reason, opts)
    end
  end

  defp build_request_state(state, plan_attrs) do
    case AgentInfra.build_request(plan_attrs) do
      {:ok, request} -> {:ok, %{state | request: request}}
      {:error, reason} -> {:error, {:plan, reason, state}}
    end
  end

  defp resolve_provider_state(state, opts) do
    case resolve_provider(opts, state.provider_id) do
      {:ok, provider_module} -> {:ok, %{state | provider_module: provider_module}}
      {:error, reason} -> {:error, {:provider, reason, state}}
    end
  end

  defp validate_request_state(state, opts) do
    case validate_request(state.provider_module, state.request, opts) do
      :ok -> {:ok, state}
      {:error, reason} -> {:error, {:validate, reason, state}}
    end
  end

  defp provision_state(state, opts) do
    case provision(state.provider_module, state.request, opts) do
      {:ok, instance_ref} -> {:ok, %{state | instance_ref: instance_ref}}
      {:error, reason} -> maybe_fallback_provision(state, reason, opts)
    end
  end

  defp maybe_fallback_provision(state, reason, opts) do
    cond do
      Keyword.get(opts, :provider_module) ->
        {:error, {:provision, reason, state}}

      not fallback_reason?(reason) ->
        {:error, {:provision, reason, state}}

      true ->
        case try_fallback_provision(state, reason, opts) do
          {:ok, updated_state} -> {:ok, updated_state}
          :no_fallback -> {:error, {:provision, reason, state}}
          {:error, fallback_reason} -> {:error, {:provision, fallback_reason, state}}
        end
    end
  end

  defp try_fallback_provision(state, reason, opts) do
    fallback_ids =
      opts
      |> fallback_provider_ids()
      |> List.wrap()
      |> Enum.map(&to_string/1)
      |> Enum.reject(&(&1 == to_string(state.provider_id)))

    if fallback_ids == [] do
      :no_fallback
    else
      fallback_ids
      |> Enum.reduce_while({:error, :no_fallback}, fn provider_id, _acc ->
        case resolve_provider_module(provider_id, opts) do
          {:ok, provider_module} ->
            request = update_request_provider(state.request, provider_id)

            case validate_request(provider_module, request, opts) do
              :ok ->
                case provision(provider_module, request, opts) do
                  {:ok, instance_ref} ->
                    {:halt,
                     {:ok,
                      %{
                        state
                        | provider_id: provider_id,
                          provider_module: provider_module,
                          request: request,
                          instance_ref: instance_ref
                      }}}

                  {:error, fallback_reason} ->
                    {:cont,
                     {:error,
                      %{
                        primary: reason,
                        fallback: fallback_reason,
                        fallback_provider: provider_id
                      }}}
                end

              {:error, fallback_reason} ->
                {:cont,
                 {:error,
                  %{primary: reason, fallback: fallback_reason, fallback_provider: provider_id}}}
            end

          {:error, fallback_reason} ->
            {:cont,
             {:error,
              %{primary: reason, fallback: fallback_reason, fallback_provider: provider_id}}}
        end
      end)
      |> case do
        {:ok, _state} = ok -> ok
        {:error, :no_fallback} -> :no_fallback
        {:error, fallback_reason} -> {:error, fallback_reason}
      end
    end
  end

  defp mark_running_state(state) do
    case mark_running(state.run, state.provider_id, state.instance_ref) do
      {:ok, run} -> {:ok, %{state | run: run}}
      {:error, reason} -> {:error, {:mark_running, reason, state}}
    end
  end

  defp persist_results(run, started_at, duration_ms, {:ok, results}) do
    update_run(run, %{
      status: :passed,
      check_results: %{"checks" => results.checks},
      metrics: Map.merge(%{"duration_ms" => duration_ms}, quality_metrics(results)),
      resource_usage: results.resource_usage,
      coverage_delta: results.coverage_delta,
      started_at: started_at,
      completed_at: DateTime.utc_now() |> DateTime.truncate(:second)
    })
  end

  defp persist_results(run, started_at, duration_ms, {:error, results}) do
    update_run(run, %{
      status: :failed,
      check_results: %{"checks" => results.checks},
      metrics: Map.merge(%{"duration_ms" => duration_ms}, quality_metrics(results)),
      resource_usage: results.resource_usage,
      coverage_delta: results.coverage_delta,
      started_at: started_at,
      completed_at: DateTime.utc_now() |> DateTime.truncate(:second)
    })
    |> case do
      {:ok, run} -> {:error, run}
      {:error, changeset} -> {:error, changeset}
    end
  end

  defp mark_running(run, provider_id, instance_ref) do
    update_run(run, %{
      status: :running,
      provider: normalize_provider_id(provider_id),
      instance_ref: normalize_instance_ref(instance_ref),
      started_at: DateTime.utc_now() |> DateTime.truncate(:second)
    })
  end

  defp update_run(run, attrs) do
    run
    |> ValidationRun.changeset(attrs)
    |> Repo.update()
  end

  defp resolve_provider(opts, provider_id) do
    case Keyword.get(opts, :provider_module) do
      nil -> resolve_provider_module(provider_id, opts)
      module -> {:ok, module}
    end
  end

  defp resolve_provider_module(provider_id, opts) do
    case Keyword.get(opts, :providers) do
      nil -> AgentInfra.provider_module(provider_id)
      providers -> AgentInfra.provider_module(provider_id, providers)
    end
  end

  defp update_request_provider(request, provider_id) do
    %{request | provider: to_string(provider_id)}
  end

  defp fallback_provider_ids(opts) do
    Keyword.get(opts, :fallback_provider_ids) ||
      Application.get_env(:micelio, :agent_infra_fallback_providers, ["fly"])
  end

  defp fallback_reason?(reason) when is_atom(reason) do
    reason in [:capacity, :provider_unavailable, :unavailable, :timeout]
  end

  defp fallback_reason?({reason, _detail}) when is_atom(reason) do
    fallback_reason?(reason)
  end

  defp fallback_reason?(%{code: code}) when is_binary(code) do
    code in ["capacity", "provider_unavailable", "unavailable", "timeout"]
  end

  defp fallback_reason?(%{"code" => code}) when is_binary(code) do
    code in ["capacity", "provider_unavailable", "unavailable", "timeout"]
  end

  defp fallback_reason?(_reason), do: false

  defp validate_request(provider_module, request, opts) do
    Code.ensure_loaded(provider_module)

    if function_exported?(provider_module, :validate_request, 2) do
      provider_module.validate_request(request, provider_opts(opts))
    else
      if function_exported?(provider_module, :validate_request, 1) do
        provider_module.validate_request(request)
      else
        :ok
      end
    end
  end

  defp provision(provider_module, request, opts) do
    if function_exported?(provider_module, :provision, 2) do
      provider_module.provision(request, provider_opts(opts))
    else
      provider_module.provision(request)
    end
  end

  defp normalize_instance_ref(ref) when is_map(ref), do: ref
  defp normalize_instance_ref(ref), do: %{"ref" => inspect(ref)}

  defp normalize_provider_id(nil), do: nil
  defp normalize_provider_id(provider_id), do: to_string(provider_id)

  defp add_quality_scores({:ok, results}, checks) do
    scores = quality_scores(checks, results)
    {:ok, Map.merge(results, %{quality_scores: scores, quality_score: scores["overall"]})}
  end

  defp add_quality_scores({:error, results}, checks) do
    scores = quality_scores(checks, results)
    {:error, Map.merge(results, %{quality_scores: scores, quality_score: scores["overall"]})}
  end

  defp enforce_quality_threshold({:ok, results}, min_quality_score)
       when is_number(min_quality_score) do
    quality_score = Map.get(results, :quality_score)

    if is_number(quality_score) and quality_score < min_quality_score do
      {:error,
       Map.merge(results, %{
         quality_threshold_failed: true,
         quality_threshold_min: min_quality_score
       })}
    else
      {:ok, results}
    end
  end

  defp enforce_quality_threshold(result, _min_quality_score), do: result

  defp quality_scores(checks, results) do
    results_by_id = Map.new(results.checks, &{&1["id"], &1})

    {totals, passes} =
      Enum.reduce(checks, {%{}, %{}}, fn check, {total_acc, pass_acc} ->
        kind = to_string(Map.get(check, :kind, "unknown"))
        check_id = to_string(Map.get(check, :id))
        total_acc = Map.update(total_acc, kind, 1, &(&1 + 1))

        pass_acc =
          case Map.get(results_by_id, check_id) do
            %{"exit_code" => 0} -> Map.update(pass_acc, kind, 1, &(&1 + 1))
            _ -> pass_acc
          end

        {total_acc, pass_acc}
      end)

    scores =
      Enum.reduce(totals, %{}, fn {kind, total}, acc ->
        passed = Map.get(passes, kind, 0)
        Map.put(acc, kind, round(passed / total * 100))
      end)

    overall =
      case map_size(scores) do
        0 -> 0
        size -> round(Enum.sum(Map.values(scores)) / size)
      end

    Map.put(scores, "overall", overall)
  end

  defp quality_metrics(%{quality_scores: scores, quality_score: overall} = results) do
    %{"quality_scores" => scores, "quality_score" => overall}
    |> maybe_put_quality_threshold(results)
  end

  defp quality_metrics(_results), do: %{}

  defp maybe_put_quality_threshold(metrics, %{quality_threshold_failed: failed} = results) do
    metrics
    |> Map.put("quality_threshold_failed", failed)
    |> maybe_put_quality_threshold_min(results)
  end

  defp maybe_put_quality_threshold(metrics, _results), do: metrics

  defp maybe_put_quality_threshold_min(metrics, %{quality_threshold_min: min})
       when is_number(min) do
    Map.put(metrics, "quality_threshold_min", min)
  end

  defp maybe_put_quality_threshold_min(metrics, _results), do: metrics

  defp fail_run(state, stage, reason, opts) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    error_payload = %{
      "stage" => to_string(stage),
      "reason" => inspect(reason)
    }

    if state.provider_module && state.instance_ref do
      safe_terminate(state.provider_module, state.instance_ref, opts)
    end

    update_run(state.run, %{
      status: :failed,
      provider: normalize_provider_id(state.provider_id),
      check_results: %{"checks" => [], "error" => error_payload},
      metrics: %{"failure_stage" => to_string(stage)},
      started_at: state.run.started_at || now,
      completed_at: now
    })
    |> case do
      {:ok, run} -> {:error, run}
      {:error, changeset} -> {:error, changeset}
    end
  end

  defp safe_terminate(provider_module, instance_ref, opts) do
    if function_exported?(provider_module, :terminate, 2) do
      provider_module.terminate(instance_ref, provider_opts(opts))
    else
      provider_module.terminate(instance_ref)
    end
  rescue
    _ -> :ok
  end

  defp notify(nil, _message), do: :ok

  defp notify(pid, message) when is_pid(pid) do
    send(pid, message)
    :ok
  end

  defp provider_opts(opts) do
    Keyword.get(opts, :provider_opts, [])
  end

  defp plan_attrs(attrs, opts) do
    provider_id =
      Map.get(attrs, :provider) ||
        Map.get(attrs, "provider") ||
        Keyword.get(opts, :provider_id, "aws")

    Map.merge(
      %{
        provider: provider_id,
        image: Keyword.get(opts, :image, @default_image),
        cpu_cores: Keyword.get(opts, :cpu_cores, 2),
        memory_mb: Keyword.get(opts, :memory_mb, 4096),
        disk_gb: Keyword.get(opts, :disk_gb, 20),
        ttl_seconds: Keyword.get(opts, :ttl_seconds, 1800),
        network: Keyword.get(opts, :network, "egress")
      },
      attrs
    )
  end
end
