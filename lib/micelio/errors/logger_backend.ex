defmodule Micelio.Errors.LoggerBackend do
  @moduledoc false

  alias Micelio.Errors.Capture
  alias Micelio.Errors.Config

  @default_level :error
  def init(__MODULE__) do
    {:ok,
     %{
       errors: nil,
       level: @default_level,
       formatter: Logger.Formatter.compile("$message")
     }}
  end

  # New Logger format (OTP 21+)
  def handle_event({:log, level, _gl, {Logger, msg, ts, md}}, state) do
    do_handle_log(level, msg, ts, md, state)
  end

  # Old Logger format (for compatibility)
  def handle_event({level, _gl, {Logger, msg, ts, md}}, state)
      when level in [:debug, :info, :notice, :warning, :warn, :error] do
    do_handle_log(level, msg, ts, md, state)
  end

  def handle_event(:flush, state), do: {:ok, state}

  # Catch-all for any other event format
  def handle_event(_event, state), do: {:ok, state}

  defp do_handle_log(level, msg, ts, md, state) do
    level = normalize_level(level)

    if should_capture?(level, state) do
      message =
        Logger.Formatter.format(state.formatter, level, msg, ts, md)
        |> IO.iodata_to_binary()
        |> String.trim()

      Capture.capture_message(message, level_to_severity(level),
        kind: :exception,
        metadata: Map.new(md),
        source: :logger,
        errors: state.errors
      )
    end

    {:ok, state}
  end

  def handle_call({:configure, opts}, state) do
    {:ok, :ok, Map.merge(state, Map.new(opts))}
  end

  def handle_call(_msg, state), do: {:ok, :ok, state}

  def code_change(_old_vsn, state, _extra), do: {:ok, state}

  def terminate(_reason, _state), do: :ok

  defp should_capture?(level, state) do
    Config.capture_enabled?(errors: state.errors) and
      Logger.compare_levels(level, state.level) != :lt
  end

  defp normalize_level(:warn), do: :warning
  defp normalize_level(level), do: level

  defp level_to_severity(:debug), do: :debug
  defp level_to_severity(:info), do: :info
  defp level_to_severity(:warning), do: :warning
  defp level_to_severity(:error), do: :error
  defp level_to_severity(_level), do: :error
end
