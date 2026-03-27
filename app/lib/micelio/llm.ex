defmodule Micelio.LLM do
  @moduledoc false

  @doc "Returns configured LLM models that can be selected per repository."
  def repository_models do
    Application.get_env(:micelio, :repository_llm_models, [])
  end

  @doc "Returns configured LLM models for a specific account."
  def repository_models_for_account(%{llm_models: models}) when is_list(models) do
    available = repository_models()

    models =
      if available == [] do
        models
      else
        Enum.filter(models, &(&1 in available))
      end

    if models == [], do: available, else: models
  end

  def repository_models_for_account(_account), do: repository_models()

  @doc "Returns the default LLM model for new repositories."
  def repository_default_model do
    Application.get_env(:micelio, :repository_llm_default) || List.first(repository_models())
  end

  @doc "Returns the default LLM model for a specific account."
  def repository_default_model_for_account(%{llm_default_model: model})
      when is_binary(model) and model != "" do
    model
  end

  def repository_default_model_for_account(account) do
    repository_models_for_account(account)
    |> List.first()
    |> case do
      nil -> repository_default_model()
      model -> model
    end
  end

  @doc "Returns select options for repository LLM models."
  def repository_model_options do
    Enum.map(repository_models(), &{&1, &1})
  end

  @doc "Returns select options for repository LLM models by account."
  def repository_model_options_for_account(account) do
    account
    |> repository_models_for_account()
    |> Enum.map(&{&1, &1})
  end
end
