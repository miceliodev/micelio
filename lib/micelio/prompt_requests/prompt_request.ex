defmodule Micelio.PromptRequests.PromptRequest do
  use Micelio.Schema

  import Ecto.Changeset

  alias Micelio.PromptRequests.PromptSuggestion

  @origin_values [:ai_generated, :ai_assisted, :human]
  @review_status_values [:pending, :accepted, :rejected]

  schema "prompt_requests" do
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

    belongs_to :repository, Micelio.Repositories.Repository
    belongs_to :user, Micelio.Accounts.User
    belongs_to :reviewed_by, Micelio.Accounts.User
    belongs_to :curated_by, Micelio.Accounts.User
    belongs_to :session, Micelio.Sessions.Session
    belongs_to :parent_prompt_request, __MODULE__
    belongs_to :prompt_template, Micelio.PromptRequests.PromptTemplate
    has_many :suggestions, PromptSuggestion
    has_many :validation_runs, Micelio.ValidationEnvironments.ValidationRun

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(prompt_request, attrs) do
    prompt_request
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
      :parent_prompt_request_id,
      :prompt_template_id
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

  @doc "Changeset for creating a simple prompt request (title + description only)."
  def simple_changeset(prompt_request, attrs) do
    prompt_request
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

  def attestation_payload(%__MODULE__{} = prompt_request) do
    %{
      "origin" => origin_value(prompt_request.origin),
      "model" => prompt_request.model,
      "model_version" => prompt_request.model_version,
      "token_count" => prompt_request.token_count,
      "generated_at" => format_datetime(prompt_request.generated_at),
      "user_id" => prompt_request.user_id,
      "repository_id" => prompt_request.repository_id
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

  @doc "Changeset for changing prompt request status (open/closed)."
  def status_changeset(prompt_request, status) do
    prompt_request
    |> change(%{status: status})
    |> validate_inclusion(:status, ["open", "closed"])
  end

  @doc "Changeset for reviewing a prompt request."
  def review_changeset(prompt_request, attrs) do
    prompt_request
    |> cast(attrs, [:review_status, :reviewed_at, :reviewed_by_id])
    |> validate_inclusion(:review_status, @review_status_values)
  end

  @doc "Changeset for curating a prompt request."
  def curation_changeset(prompt_request, attrs) do
    prompt_request
    |> cast(attrs, [:curated_at, :curated_by_id])
  end
end
