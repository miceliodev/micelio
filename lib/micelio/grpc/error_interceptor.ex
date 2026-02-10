defmodule Micelio.GRPC.ErrorInterceptor do
  @moduledoc """
  gRPC server interceptor that converts {:error, %GRPC.RPCError{}} tuples
  returned from handlers into raised exceptions.

  This works around a limitation in the grpc library where error tuples
  are wrapped in {:ok, stream, reply} and passed to the protobuf encoder.
  """

  @behaviour GRPC.Server.Interceptor

  @impl true
  def init(opts), do: opts

  @impl true
  def call(req, stream, next, _opts) do
    case next.(req, stream) do
      {:ok, _stream, {:error, %GRPC.RPCError{} = error}} ->
        raise error

      {:ok, _stream, {:error, error}} when is_exception(error) ->
        raise error

      other ->
        other
    end
  end
end
