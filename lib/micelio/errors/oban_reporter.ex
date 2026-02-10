defmodule Micelio.Errors.ObanReporter do
  @moduledoc false

  alias Micelio.Errors.Capture

  @handler_id "micelio-errors-oban"
  @events [[:oban, :job, :exception], [:oban, :job, :discard]]

  def attach do
    if Code.ensure_loaded?(Oban) do
      :telemetry.attach_many(@handler_id, @events, &__MODULE__.handle_event/4, nil)
    else
      :ok
    end
  end

  def detach do
    if Code.ensure_loaded?(Oban) do
      :telemetry.detach(@handler_id)
    else
      :ok
    end
  end

  def handle_event([:oban, :job, :exception], _measurements, metadata, config) do
    reason = Map.get(metadata, :reason)
    stacktrace = Map.get(metadata, :stacktrace, [])
    {user_id, repository_id} = job_context_ids(metadata)

    Capture.capture_exception(reason,
      kind: :oban_job,
      error_kind: Map.get(metadata, :kind, :error),
      stacktrace: stacktrace,
      metadata: job_metadata(metadata),
      user_id: user_id,
      repository_id: repository_id,
      source: :oban,
      errors: errors_config(config)
    )
  end

  def handle_event([:oban, :job, :discard], _measurements, metadata, config) do
    reason = Map.get(metadata, :reason) || Map.get(metadata, :error) || "discarded"
    {user_id, repository_id} = job_context_ids(metadata)

    Capture.capture_message("Oban job discarded: #{inspect(reason)}", :error,
      kind: :oban_job,
      metadata: job_metadata(metadata),
      user_id: user_id,
      repository_id: repository_id,
      source: :oban,
      errors: errors_config(config)
    )
  end

  def handle_event(_event, _measurements, _metadata, _config), do: :ok

  defp job_metadata(metadata) do
    job = Map.get(metadata, :job, %{})
    args = Map.get(job, :args, %{})

    correlation_id =
      Map.get(args, "correlation_id") || Map.get(args, :correlation_id) || Map.get(job, :id)

    %{
      job_id: Map.get(job, :id),
      queue: Map.get(job, :queue),
      worker: Map.get(job, :worker),
      attempt: Map.get(job, :attempt),
      max_attempts: Map.get(job, :max_attempts),
      args: args,
      correlation_id: correlation_id
    }
  end

  defp job_context_ids(metadata) do
    job = Map.get(metadata, :job, %{})
    args = Map.get(job, :args, %{})

    {
      Map.get(args, "user_id") || Map.get(args, :user_id),
      Map.get(args, "repository_id") || Map.get(args, :repository_id)
    }
  end

  defp errors_config(nil), do: nil
  defp errors_config(config) when is_list(config), do: Keyword.get(config, :errors)
  defp errors_config(config) when is_map(config), do: Map.get(config, :errors)
end
