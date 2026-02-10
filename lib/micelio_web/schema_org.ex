defmodule MicelioWeb.SchemaOrg do
  @moduledoc """
  Schema.org JSON-LD helpers for SEO metadata.
  """

  alias Micelio.Accounts.Account
  alias Micelio.Repositories.Repository

  @spec software_source_code(Account.t(), Project.t(), keyword() | map()) :: map()
  def software_source_code(%Account{} = account, %Repository{} = repository, opts \\ []) do
    opts = normalize_map(opts)
    url = Map.get(opts, :url)
    code_repository = Map.get(opts, :code_repository, url)
    author_url = Map.get(opts, :author_url)

    %{
      "@context" => "https://schema.org",
      "@type" => "SoftwareSourceCode",
      "name" => repository.name,
      "description" => repository.description,
      "url" => url,
      "codeRepository" => code_repository,
      "identifier" => "#{account.handle}/#{repository.handle}",
      "author" => author(account, author_url)
    }
    |> drop_nil_and_blank()
  end

  @spec encode(map()) :: String.t()
  def encode(schema) when is_map(schema) do
    schema
    |> drop_nil_and_blank()
    |> Jason.encode!()
  end

  defp author(%Account{} = account, url) do
    type =
      cond do
        Account.organization?(account) -> "Organization"
        Account.user?(account) -> "Person"
        true -> nil
      end

    if is_binary(type) do
      %{
        "@type" => type,
        "name" => account.handle,
        "url" => url
      }
      |> drop_nil_and_blank()
    end
  end

  defp drop_nil_and_blank(map) when is_map(map) do
    map
    |> Enum.reject(fn
      {_key, nil} -> true
      {_key, value} when is_binary(value) -> String.trim(value) == ""
      _ -> false
    end)
    |> Map.new()
  end

  defp normalize_map(opts) when is_map(opts), do: opts
  defp normalize_map(opts) when is_list(opts), do: Map.new(opts)
end
