defmodule Mix.Tasks.Micelio.Rollups.Rebuild do
  @shortdoc "Rebuilds mic rollup indexes"

  @moduledoc """
  Rebuild mic rollup indexes for a repository or all projects.

      mix micelio.rollups.rebuild --repository <id> [--from 1] [--to 1000]
      mix micelio.rollups.rebuild --repository <id> --from-head [--from 1]
      mix micelio.rollups.rebuild
  """

  use Mix.Task

  alias Micelio.Mic.RollupRebuilder
  alias Micelio.Repositories

  @impl true
  def run(args) do
    Mix.Task.run("app.start")

    {opts, _} =
      OptionParser.parse(args,
        strict: [repository: :string, from: :integer, to: :integer, from_head: :boolean]
      )

    case opts do
      %{project: repository_id, from_head: true} ->
        from_position = Keyword.get(opts, :from, 1)
        _ = RollupRebuilder.rebuild_from_head(repository_id, from_position)
        Mix.shell().info("Rebuilt rollups from head for project #{repository_id}.")

      %{project: repository_id} ->
        from_position = Keyword.get(opts, :from, 1)
        to_position = Keyword.get(opts, :to, from_position)
        _ = RollupRebuilder.rebuild(repository_id, from_position, to_position)
        Mix.shell().info("Rebuilt rollups for project #{repository_id}.")

      _ ->
        Repositories.list_repositories()
        |> Enum.each(fn repository ->
          _ = RollupRebuilder.rebuild_from_head(repository.id, 1)
        end)

        Mix.shell().info("Rebuilt rollups for all repositories.")
    end
  end
end
