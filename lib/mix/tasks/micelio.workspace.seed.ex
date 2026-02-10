defmodule Mix.Tasks.Micelio.Workspace.Seed do
  @shortdoc "Seeds the micelio workspace from a local checkout"

  @moduledoc """
  Seeds the micelio/micelio repository storage from a local checkout.

      mix micelio.workspace.seed --path /path/to/checkout
  """

  use Mix.Task

  alias Micelio.Repositories

  @impl true
  def run(args) do
    Mix.Task.run("app.start")

    {opts, _} = OptionParser.parse(args, strict: [path: :string])
    root_path = Keyword.get(opts, :path, File.cwd!())

    case Repositories.seed_micelio_workspace(root_path) do
      {:ok, %{repository: repository, already_seeded: true}} ->
        Mix.shell().info(
          "Micelio workspace already seeded: #{repository.handle}/#{repository.name}"
        )

      {:ok, %{repository: repository, file_count: file_count}} ->
        Mix.shell().info(
          "Seeded Micelio workspace: #{repository.handle}/#{repository.name} (#{file_count} files)"
        )

      {:error, reason} ->
        Mix.raise("Failed to seed Micelio workspace: #{inspect(reason)}")
    end
  end
end
