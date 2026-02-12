defmodule Micelio.OAuth.Scopes do
  @moduledoc """
  Central registry of all OAuth2 scopes for the Micelio API.

  Scopes follow a `domain:action` pattern where the domain maps to
  a resource type and the action describes the level of access.
  """

  @all_scopes [
    %{name: "repositories:read", description: "List and get repositories"},
    %{name: "repositories:write", description: "Create, update, and delete repositories"},
    %{name: "sessions:read", description: "List and get sessions"},
    %{name: "sessions:write", description: "Start, land, and abandon sessions"},
    %{name: "content:read", description: "Read files, trees, and blame"},
    %{name: "organizations:read", description: "List and get organizations"},
    %{name: "prompt_requests:read", description: "List and get prompt requests"},
    %{name: "prompt_requests:write", description: "Create prompt requests"},
    %{name: "tokens:read", description: "Read token pool balance"},
    %{name: "tokens:write", description: "Update token pool and contribute tokens"}
  ]

  @scope_names Enum.map(@all_scopes, & &1.name)

  @doc """
  Returns all defined scopes as Boruta-compatible scope structs.
  """
  def all do
    Enum.map(@all_scopes, &to_boruta_scope/1)
  end

  @doc """
  Returns all scope names as a list of strings.
  """
  def names, do: @scope_names

  @doc """
  Returns all scope definitions with name and description.
  """
  def definitions, do: @all_scopes

  @doc """
  Returns a map of scope name to description, suitable for OpenAPI specs.
  """
  def descriptions do
    Map.new(@all_scopes, fn s -> {s.name, s.description} end)
  end

  @doc """
  Checks whether a scope name is valid.
  """
  def valid?(scope_name), do: scope_name in @scope_names

  @doc """
  Parses a space-separated scope string into a list of scope name strings.

  When the input is nil or empty, returns all scope names (backwards compatible
  with existing tokens that have no scopes set).
  """
  def from_string(nil), do: @scope_names
  def from_string(""), do: @scope_names

  def from_string(scope_string) when is_binary(scope_string) do
    scope_string
    |> String.split(" ", trim: true)
    |> Enum.filter(&valid?/1)
  end

  defp to_boruta_scope(%{name: name}) do
    %Boruta.Oauth.Scope{name: name}
  end
end
