defmodule Micelio.CliReference do
  @moduledoc """
  Provides CLI reference documentation generated from `hif --docs`.

  The documentation is loaded from `priv/cli-reference.json` at compile time.
  To update, run: `hif --docs > priv/cli-reference.json`
  """

  @external_resource "priv/cli-reference.json"

  @cli_docs "priv/cli-reference.json"
            |> File.read!()
            |> Jason.decode!()

  @doc """
  Returns the full CLI documentation as a map.
  """
  def docs, do: @cli_docs

  @doc """
  Returns the CLI version.
  """
  def version, do: @cli_docs["version"]

  @doc """
  Returns the CLI description.
  """
  def description, do: @cli_docs["description"]

  @doc """
  Returns the tagline.
  """
  def tagline, do: @cli_docs["tagline"]

  @doc """
  Returns the introduction section.
  """
  def introduction, do: @cli_docs["introduction"]

  @doc """
  Returns the list of concepts.
  """
  def concepts, do: @cli_docs["concepts"]

  @doc """
  Returns the quick start guide.
  """
  def quick_start, do: @cli_docs["quick_start"]

  @doc """
  Returns all commands.
  """
  def commands, do: @cli_docs["commands"]

  @doc """
  Returns commands grouped by category.
  """
  def commands_by_category do
    @cli_docs["commands"]
    |> Enum.group_by(& &1["category"])
  end

  @doc """
  Returns a specific command by name.
  """
  def get_command(name) do
    Enum.find(@cli_docs["commands"], fn cmd ->
      cmd["name"] == name
    end)
  end

  @doc """
  Returns global options.
  """
  def global_options, do: @cli_docs["global_options"]

  @doc """
  Returns environment variables.
  """
  def environment_variables, do: @cli_docs["environment_variables"]

  @doc """
  Returns error codes.
  """
  def error_codes, do: @cli_docs["error_codes"]

  @doc """
  Returns see also links.
  """
  def see_also, do: @cli_docs["see_also"]

  @doc """
  Returns installation info.
  """
  def installation, do: @cli_docs["installation"]
end
