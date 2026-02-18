defmodule Micelio.Plans.Plan do
  use Micelio.Schema

  import Ecto.Changeset

  alias Micelio.Plans.PlanSuggestion

  @origin_values [:ai_generated, :ai_assisted, :human]
  @review_status_values [:pending, :accepted, :rejected]

  schema "plans" do
    field :number, :integer
    field :title, :string
    field :description, :string
    field :prompt, :string
    field :result, :string
    field :model, :string
    field :model_version, :string
    field :origin, Ecto.Enum, values: @origin_values, default: :ai_generated
    field :review_status, Ecto.Enum, values: @review_status_values, default: :pending
    field :reviewed_at, :utc_datetime
    field :curated_at, :utc_datetime
    field :token_count, :integer
    field :generated_at, :utc_datetime
    field :system_prompt, :string
    field :conversation, :map, default: %{}
    field :attestation, :map, default: %{}
    field :execution_environment, :map
    field :execution_duration_ms, :integer
    field :validation_feedback, :string
    field :validation_iterations, :integer, default: 0
    field :status, :string, default: "open"
    field :agent, :string
    field :agent_model, :string
    field :agent_status, :string, default: "idle"

    field :sandbox_workspace_id, :string
    field :sandbox_provider, :string
    field :sandbox_status, :string, default: "none"
    field :sandbox_started_at, :utc_datetime
    field :sandbox_expires_at, :utc_datetime
    field :sandbox_metadata, :map, default: %{}
    field :forge_branch_name, :string
    field :forge_pr_provider, :string
    field :forge_pr_number, :integer
    field :forge_pr_url, :string
    field :forge_pr_state, :string
    field :forge_pr_draft, :boolean, default: true
    field :forge_pr_synced_at, :utc_datetime
    field :forge_pr_metadata, :map, default: %{}

    belongs_to :repository, Micelio.Repositories.Repository
    belongs_to :user, Micelio.Accounts.User
    belongs_to :reviewed_by, Micelio.Accounts.User
    belongs_to :curated_by, Micelio.Accounts.User
    belongs_to :session, Micelio.Sessions.Session
    belongs_to :parent_plan, __MODULE__
    belongs_to :plan_template, Micelio.Plans.PlanTemplate
    has_many :suggestions, PlanSuggestion
    has_many :messages, Micelio.Plans.PlanMessage
    has_many :acp_envelopes, Micelio.Plans.ACPEnvelope
    has_many :validation_runs, Micelio.ValidationEnvironments.ValidationRun

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(plan, attrs) do
    plan
    |> cast(attrs, [
      :title,
      :prompt,
      :result,
      :model,
      :model_version,
      :origin,
      :token_count,
      :generated_at,
      :system_prompt,
      :execution_environment,
      :execution_duration_ms,
      :parent_plan_id,
      :plan_template_id
    ])
    |> cast_generated_at(attrs)
    |> cast_conversation(attrs)
    |> normalize_text_fields()
    |> validate_required([:title, :prompt, :result, :system_prompt, :conversation, :origin])
    |> validate_length(:title, max: 120)
    |> validate_length(:model, max: 120)
    |> validate_length(:model_version, max: 120)
    |> validate_number(:token_count, greater_than_or_equal_to: 0)
    |> validate_ai_requirements()
    |> validate_conversation()
  end

  @doc "Changeset for creating a simple plan (title + description only)."
  def simple_changeset(plan, attrs) do
    plan
    |> cast(attrs, [:title, :description])
    |> validate_required([:title])
    |> validate_length(:title, max: 200)
  end

  defp cast_conversation(changeset, attrs) do
    case Map.get(attrs, :conversation) || Map.get(attrs, "conversation") do
      nil ->
        changeset

      "" ->
        put_change(changeset, :conversation, %{})

      value when is_map(value) ->
        put_change(changeset, :conversation, value)

      value when is_binary(value) ->
        case Jason.decode(value) do
          {:ok, decoded} when is_map(decoded) ->
            put_change(changeset, :conversation, decoded)

          _ ->
            add_error(changeset, :conversation, "must be valid JSON object")
        end

      _ ->
        add_error(changeset, :conversation, "must be valid JSON")
    end
  end

  defp normalize_text_fields(changeset) do
    changeset
    |> update_change(:title, &normalize_text/1)
    |> update_change(:prompt, &normalize_text/1)
    |> update_change(:result, &normalize_text/1)
    |> update_change(:model, &normalize_text/1)
    |> update_change(:model_version, &normalize_text/1)
    |> update_change(:system_prompt, &normalize_text/1)
  end

  defp normalize_text(nil), do: nil

  defp normalize_text(value) when is_binary(value) do
    value
    |> String.trim()
    |> case do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp validate_conversation(changeset) do
    validate_change(changeset, :conversation, fn :conversation, value ->
      if is_map(value) and map_size(value) > 0 do
        []
      else
        [conversation: "must include conversation history"]
      end
    end)
  end

  def origin_label(:ai_generated), do: "AI-generated"
  def origin_label(:ai_assisted), do: "AI-assisted"
  def origin_label(:human), do: "Human"
  def origin_label(nil), do: "Unknown"

  def attestation_payload(%__MODULE__{} = plan) do
    %{
      "origin" => origin_value(plan.origin),
      "model" => plan.model,
      "model_version" => plan.model_version,
      "token_count" => plan.token_count,
      "generated_at" => format_datetime(plan.generated_at),
      "user_id" => plan.user_id,
      "repository_id" => plan.repository_id
    }
  end

  defp origin_value(origin) when is_atom(origin), do: Atom.to_string(origin)
  defp origin_value(origin) when is_binary(origin), do: origin
  defp origin_value(_), do: nil

  defp format_datetime(nil), do: nil
  defp format_datetime(%DateTime{} = value), do: DateTime.to_iso8601(value)
  defp format_datetime(%NaiveDateTime{} = value), do: NaiveDateTime.to_iso8601(value)

  defp validate_ai_requirements(changeset) do
    case get_field(changeset, :origin) do
      :human ->
        changeset

      _ ->
        changeset
        |> validate_required([:model, :model_version, :token_count, :generated_at])
    end
  end

  defp cast_generated_at(changeset, attrs) do
    case Map.get(attrs, :generated_at) || Map.get(attrs, "generated_at") do
      nil ->
        changeset

      "" ->
        put_change(changeset, :generated_at, nil)

      %DateTime{} = datetime ->
        put_change(changeset, :generated_at, DateTime.truncate(datetime, :second))

      %NaiveDateTime{} = datetime ->
        dt = DateTime.from_naive!(datetime, "Etc/UTC")
        put_change(changeset, :generated_at, DateTime.truncate(dt, :second))

      value when is_binary(value) ->
        case DateTime.from_iso8601(value) do
          {:ok, datetime, _offset} ->
            put_change(changeset, :generated_at, DateTime.truncate(datetime, :second))

          {:error, _} ->
            case NaiveDateTime.from_iso8601(value) do
              {:ok, naive} ->
                dt = DateTime.from_naive!(naive, "Etc/UTC")
                put_change(changeset, :generated_at, DateTime.truncate(dt, :second))

              {:error, _} ->
                add_error(changeset, :generated_at, "must be valid datetime")
            end
        end

      _ ->
        add_error(changeset, :generated_at, "must be valid datetime")
    end
  end

  @doc "Changeset for updating sandbox state."
  def sandbox_changeset(plan, attrs) do
    plan
    |> cast(attrs, [
      :sandbox_workspace_id,
      :sandbox_provider,
      :sandbox_status,
      :sandbox_started_at,
      :sandbox_expires_at,
      :sandbox_metadata
    ])
    |> validate_inclusion(:sandbox_status, [
      "none",
      "provisioning",
      "running",
      "stopping",
      "stopped",
      "error"
    ])
    |> validate_inclusion(:sandbox_provider, ["docker", "daytona"])
  end

  @doc "Changeset for updating linked forge pull request metadata."
  def forge_pr_changeset(plan, attrs) do
    plan
    |> cast(attrs, [
      :forge_branch_name,
      :forge_pr_provider,
      :forge_pr_number,
      :forge_pr_url,
      :forge_pr_state,
      :forge_pr_draft,
      :forge_pr_synced_at,
      :forge_pr_metadata
    ])
    |> validate_inclusion(:forge_pr_provider, ["github", "gitlab"])
    |> validate_inclusion(:forge_pr_state, ["open", "closed", "merged", "draft", "unknown"])
    |> validate_length(:forge_branch_name, max: 255)
    |> validate_length(:forge_pr_url, max: 1024)
  end

  @doc "Changeset for changing plan status (open/closed)."
  def status_changeset(plan, status) do
    plan
    |> change(%{status: status})
    |> validate_inclusion(:status, ["open", "closed"])
  end

  @doc "Changeset for reviewing a plan."
  def review_changeset(plan, attrs) do
    plan
    |> cast(attrs, [:review_status, :reviewed_at, :reviewed_by_id])
    |> validate_inclusion(:review_status, @review_status_values)
  end

  @doc "Changeset for curating a plan."
  def curation_changeset(plan, attrs) do
    plan
    |> cast(attrs, [:curated_at, :curated_by_id])
  end
end
