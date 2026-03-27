defmodule MicelioWeb.ErrorCapturePlug do
  @moduledoc false

  use Plug.ErrorHandler

  import Plug.Conn

  alias Micelio.Errors.Capture

  defmacro __using__(_opts) do
    quote do
      use Plug.ErrorHandler

      @impl Plug.ErrorHandler
      def handle_errors(conn, assigns) do
        MicelioWeb.ErrorCapturePlug.handle_errors(conn, assigns)
      end
    end
  end

  def init(opts), do: opts

  def call(conn, _opts), do: conn

  def handle_errors(conn, %{kind: kind, reason: reason, stack: stacktrace}) do
    Capture.capture_exception(reason,
      kind: :plug_error,
      error_kind: kind,
      stacktrace: stacktrace,
      context: conn_context(conn),
      metadata: %{plug_kind: kind},
      source: :plug,
      errors: conn.assigns[:errors_config]
    )
  end

  defp conn_context(conn) do
    %{
      request_id: conn.assigns[:request_id] || List.first(get_resp_header(conn, "x-request-id")),
      method: conn.method,
      path: conn.request_path
    }
  end
end
