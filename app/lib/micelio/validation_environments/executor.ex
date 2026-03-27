defmodule Micelio.ValidationEnvironments.Executor do
  @moduledoc """
  Behavior for executing validation checks inside a provisioned environment.
  """

  @type instance_ref :: term()
  @type result :: %{
          required(:exit_code) => integer(),
          optional(:stdout) => String.t(),
          optional(:resource_usage) => map(),
          optional(:coverage_delta) => number()
        }

  @callback run(instance_ref(), String.t(), [String.t()], map()) :: {:ok, result()}
end
