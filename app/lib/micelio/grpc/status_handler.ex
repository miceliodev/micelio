defmodule Micelio.GRPC.StatusHandler do
  @moduledoc false

  def init(req, state) do
    {:ok, :cowboy_req.reply(200, %{"content-type" => "text/plain"}, "ok", req), state}
  end
end
