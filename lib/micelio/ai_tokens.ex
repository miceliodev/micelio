defmodule Micelio.AITokens do
  @moduledoc """
  Context helpers for AI token pools.
  """

  import Ecto.Query

  alias Ecto.Multi
  alias Micelio.Accounts.User
  alias Micelio.AITokens.EarningPolicy
  alias Micelio.AITokens.TaskBudget
  alias Micelio.AITokens.TokenContribution
  alias Micelio.AITokens.TokenEarning
  alias Micelio.AITokens.TokenPool
  alias Micelio.PromptRequests.PromptRequest
  alias Micelio.PromptRequests.PromptSuggestion
  alias Micelio.Repo
  alias Micelio.Repositories.Repository

  def get_token_pool(id), do: Repo.get(TokenPool, id)

  def get_token_pool_by_project(repository_id) do
    Repo.get_by(TokenPool, repository_id: repository_id)
  end

  def get_token_pool_by_project!(repository_id) do
    Repo.get_by!(TokenPool, repository_id: repository_id)
  end

  def create_token_pool(%Repository{} = repository, attrs \\ %{}) do
    attrs = Map.put_new(attrs, :repository_id, repository.id)

    %TokenPool{}
    |> TokenPool.changeset(attrs)
    |> Repo.insert()
  end

  def get_or_create_token_pool(%Repository{} = repository) do
    case get_token_pool_by_project(repository.id) do
      nil -> create_token_pool(repository)
      %TokenPool{} = pool -> {:ok, pool}
    end
  end

  def change_token_pool(%TokenPool{} = pool, attrs \\ %{}) do
    TokenPool.changeset(pool, attrs)
  end

  def update_token_pool(%TokenPool{} = pool, attrs) when is_map(attrs) do
    pool
    |> TokenPool.changeset(attrs)
    |> Repo.update()
  end

  def repository_usage_summary(%Repository{} = repository) do
    tokens_spent =
      Repo.one(
        from pr in PromptRequest,
          where: pr.repository_id == ^repository.id,
          select: fragment("COALESCE(?, 0)", sum(pr.token_count))
      ) || 0

    accepted_prompt_requests =
      Repo.one(
        from pr in PromptRequest,
          where: pr.repository_id == ^repository.id and pr.review_status == :accepted,
          select: count(pr.id)
      ) || 0

    total_prompt_requests =
      Repo.one(
        from pr in PromptRequest,
          where: pr.repository_id == ^repository.id,
          select: count(pr.id)
      ) || 0

    %{
      tokens_spent: tokens_spent,
      accepted_prompt_requests: accepted_prompt_requests,
      total_prompt_requests: total_prompt_requests
    }
  end

  def change_token_contribution(%TokenContribution{} = contribution, attrs \\ %{}) do
    TokenContribution.changeset(contribution, attrs)
  end

  def prompt_request_reward(%PromptRequest{} = prompt_request) do
    EarningPolicy.prompt_request_reward(prompt_request.token_count)
  end

  def ensure_prompt_request_earning(repo \\ Repo, %PromptRequest{} = prompt_request) do
    case repo.get_by(TokenEarning,
           prompt_request_id: prompt_request.id,
           reason: :prompt_request_accepted
         ) do
      %TokenEarning{} ->
        {:ok, :skipped}

      nil ->
        amount = prompt_request_reward(prompt_request)

        if amount > 0 do
          insert_token_earning(
            repo,
            %{
              amount: amount,
              reason: :prompt_request_accepted,
              repository_id: prompt_request.repository_id,
              user_id: prompt_request.user_id,
              prompt_request_id: prompt_request.id
            },
            [:prompt_request_id, :user_id, :reason]
          )
        else
          {:ok, :skipped}
        end
    end
  end

  def prompt_suggestion_reward(%PromptSuggestion{} = suggestion) do
    EarningPolicy.prompt_suggestion_reward(suggestion.suggestion)
  end

  def ensure_prompt_suggestion_earning(
        repo \\ Repo,
        %PromptSuggestion{} = suggestion,
        %PromptRequest{} = prompt_request
      ) do
    case repo.get_by(TokenEarning,
           prompt_request_id: prompt_request.id,
           user_id: suggestion.user_id,
           reason: :prompt_suggestion_submitted
         ) do
      %TokenEarning{} ->
        {:ok, :skipped}

      nil ->
        amount = prompt_suggestion_reward(suggestion)

        if amount > 0 do
          insert_token_earning(
            repo,
            %{
              amount: amount,
              reason: :prompt_suggestion_submitted,
              repository_id: prompt_request.repository_id,
              user_id: suggestion.user_id,
              prompt_request_id: prompt_request.id,
              prompt_suggestion_id: suggestion.id
            },
            [:prompt_request_id, :user_id, :reason]
          )
        else
          {:ok, :skipped}
        end
    end
  end

  def contribute_tokens(%Repository{} = repository, %User{} = user, attrs) when is_map(attrs) do
    attrs =
      attrs
      |> Map.new(fn {key, value} -> {to_string(key), value} end)
      |> Map.put_new("repository_id", repository.id)
      |> Map.put_new("user_id", user.id)

    Multi.new()
    |> Multi.insert(:contribution, TokenContribution.changeset(%TokenContribution{}, attrs))
    |> Multi.run(:pool, fn repo, _changes ->
      TokenPool
      |> where([pool], pool.repository_id == ^repository.id)
      |> lock("FOR UPDATE")
      |> repo.one()
      |> case do
        nil -> repo.insert(TokenPool.changeset(%TokenPool{}, %{repository_id: repository.id}))
        %TokenPool{} = pool -> {:ok, pool}
      end
    end)
    |> Multi.update(:pool_update, fn %{pool: pool, contribution: contribution} ->
      TokenPool.changeset(pool, %{balance: pool.balance + contribution.amount})
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{contribution: contribution, pool_update: pool}} -> {:ok, contribution, pool}
      {:error, :contribution, %Ecto.Changeset{} = changeset, _changes} -> {:error, changeset}
      {:error, :pool, %Ecto.Changeset{} = changeset, _changes} -> {:error, changeset}
      {:error, :pool_update, %Ecto.Changeset{} = changeset, _changes} -> {:error, changeset}
    end
  end

  def get_task_budget_for_prompt_request(%PromptRequest{} = prompt_request) do
    Repo.get_by(TaskBudget, prompt_request_id: prompt_request.id)
  end

  def ensure_budget_for_prompt_request(%PromptRequest{} = prompt_request) do
    case prompt_request.origin do
      :human ->
        :ok

      _ ->
        case get_task_budget_for_prompt_request(prompt_request) do
          nil ->
            {:error, :missing_budget}

          %TaskBudget{} = budget ->
            required_tokens = prompt_request.token_count || 0

            cond do
              budget.amount <= 0 ->
                {:error, :insufficient_tokens}

              required_tokens > 0 and required_tokens > budget.amount ->
                {:error, :insufficient_tokens}

              true ->
                :ok
            end
        end
    end
  end

  def change_task_budget(%TaskBudget{} = task_budget, attrs \\ %{}) do
    TaskBudget.changeset(task_budget, attrs)
  end

  def upsert_task_budget(%PromptRequest{} = prompt_request, attrs) when is_map(attrs) do
    attrs =
      attrs
      |> Map.new(fn {key, value} -> {to_string(key), value} end)
      |> Map.take(["amount"])

    Multi.new()
    |> Multi.run(:pool, fn repo, _changes ->
      fetch_or_create_pool(repo, prompt_request.repository_id)
    end)
    |> Multi.run(:budget, fn repo, _changes -> fetch_budget(repo, prompt_request.id) end)
    |> Multi.run(:budget_changeset, fn _repo, %{budget: budget, pool: pool} ->
      changeset =
        budget
        |> TaskBudget.changeset(attrs)
        |> Ecto.Changeset.put_change(:prompt_request_id, prompt_request.id)
        |> Ecto.Changeset.put_change(:token_pool_id, pool.id)

      if changeset.valid?, do: {:ok, changeset}, else: {:error, changeset}
    end)
    |> Multi.run(:pool_update, fn repo,
                                  %{pool: pool, budget: budget, budget_changeset: changeset} ->
      new_amount = Ecto.Changeset.get_field(changeset, :amount) || 0
      old_amount = budget.amount || 0
      delta = new_amount - old_amount
      new_reserved = pool.reserved + delta

      cond do
        new_reserved < 0 ->
          {:error, :invalid_reserved}

        new_reserved > pool.balance ->
          {:error, :insufficient_tokens}

        true ->
          repo.update(TokenPool.changeset(pool, %{reserved: new_reserved}))
      end
    end)
    |> Multi.run(:budget_save, fn repo, %{budget_changeset: changeset} ->
      repo.insert_or_update(changeset)
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{budget_save: budget, pool_update: pool}} ->
        {:ok, budget, pool}

      {:error, :budget_changeset, %Ecto.Changeset{} = changeset, _changes} ->
        {:error, changeset}

      {:error, :pool_update, :insufficient_tokens, _changes} ->
        {:error, :insufficient_tokens}

      {:error, :pool_update, :invalid_reserved, _changes} ->
        {:error, :invalid_reserved}

      {:error, :pool_update, %Ecto.Changeset{} = changeset, _changes} ->
        {:error, changeset}

      {:error, :budget_save, %Ecto.Changeset{} = changeset, _changes} ->
        {:error, changeset}
    end
  end

  defp fetch_or_create_pool(repo, repository_id) do
    TokenPool
    |> where([pool], pool.repository_id == ^repository_id)
    |> lock("FOR UPDATE")
    |> repo.one()
    |> case do
      nil -> repo.insert(TokenPool.changeset(%TokenPool{}, %{repository_id: repository_id}))
      %TokenPool{} = pool -> {:ok, pool}
    end
  end

  defp fetch_budget(repo, prompt_request_id) do
    TaskBudget
    |> where([budget], budget.prompt_request_id == ^prompt_request_id)
    |> lock("FOR UPDATE")
    |> repo.one()
    |> case do
      nil -> {:ok, %TaskBudget{prompt_request_id: prompt_request_id}}
      %TaskBudget{} = budget -> {:ok, budget}
    end
  end

  defp insert_token_earning(repo, attrs, conflict_target) do
    changeset = TokenEarning.changeset(%TokenEarning{}, attrs)

    case repo.insert(changeset, on_conflict: :nothing, conflict_target: conflict_target) do
      {:ok, %TokenEarning{id: nil}} -> {:ok, :skipped}
      {:ok, %TokenEarning{} = earning} -> {:ok, earning}
      {:error, %Ecto.Changeset{} = changeset} -> {:error, changeset}
    end
  end
end
