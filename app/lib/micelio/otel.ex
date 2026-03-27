defmodule Micelio.OTel do
  @moduledoc false

  def setup do
    OpentelemetryBandit.setup()
    OpentelemetryPhoenix.setup(adapter: :bandit)
    OpentelemetryEcto.setup([:micelio, :repo])
    OpentelemetryLoggerMetadata.setup()
  end
end
