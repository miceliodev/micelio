defmodule Micelio.AgentInfra.SessionRequest do
  @moduledoc """
  Defines the session manager request payload for sandboxed sessions.
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias Micelio.AgentInfra.ProvisioningPlan

  @primary_key false
  embedded_schema do
    field :purpose, :string
    field :workspace_ref, :string
    field :command, {:array, :string}, default: []
    field :env, :map, default: %{}
    field :working_dir, :string, default: "/workspace"
    field :ttl_seconds, :integer
    field :metadata, :map, default: %{}
    embeds_one :plan, ProvisioningPlan, on_replace: :update
  end

  @type t :: %__MODULE__{
          purpose: String.t() | nil,
          workspace_ref: String.t() | nil,
          command: [String.t()],
          env: map(),
          working_dir: String.t() | nil,
          ttl_seconds: integer() | nil,
          metadata: map(),
          plan: ProvisioningPlan.t() | nil
        }

  @doc """
  Builds a changeset for a session request.
  """
  def changeset(request, attrs) do
    request
    |> cast(attrs, [
      :purpose,
      :workspace_ref,
      :command,
      :env,
      :working_dir,
      :ttl_seconds,
      :metadata
    ])
    |> cast_embed(:plan, required: true)
    |> validate_required([:purpose, :workspace_ref, :working_dir])
    |> validate_inclusion(:purpose, purpose_values())
    |> validate_length(:workspace_ref, min: 1, max: 200)
    |> validate_length(:working_dir, min: 1, max: 256)
    |> validate_number(:ttl_seconds, greater_than: 0)
    |> validate_command()
    |> validate_env()
    |> validate_working_dir()
  end

  defp purpose_values do
    ~w(agent validation review ci debug)
  end

  defp validate_command(changeset) do
    validate_change(changeset, :command, fn :command, command ->
      invalid =
        command
        |> Enum.reject(&valid_command_segment?/1)

      if invalid == [] do
        []
      else
        [command: "must contain non-empty strings"]
      end
    end)
  end

  defp valid_command_segment?(segment) do
    is_binary(segment) and String.trim(segment) != ""
  end

  defp validate_env(changeset) do
    validate_change(changeset, :env, fn :env, env ->
      invalid =
        env
        |> Enum.reject(fn {key, value} ->
          is_binary(key) and (is_binary(value) or is_number(value) or is_boolean(value))
        end)

      if invalid == [] do
        []
      else
        [env: "must contain string keys and string, number, or boolean values"]
      end
    end)
  end

  defp validate_working_dir(changeset) do
    validate_change(changeset, :working_dir, fn :working_dir, working_dir ->
      if String.starts_with?(working_dir, "/") do
        []
      else
        [working_dir: "must be an absolute path"]
      end
    end)
  end
end
