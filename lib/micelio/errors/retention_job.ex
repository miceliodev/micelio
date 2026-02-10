defmodule Micelio.Errors.RetentionJob do
  @moduledoc false

  alias Micelio.Errors.Retention

  def perform(_job) do
    Retention.run()
  end
end
