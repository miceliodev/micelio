defmodule Micelio.Docs.GrpcDocs do
  @moduledoc """
  Generates documentation pages from .proto files at compile time.

  Uses `@external_resource` to track proto files, so the module only
  recompiles when a proto file changes.
  """

  alias Micelio.Docs.ProtoParser

  @protos_dir Application.app_dir(:micelio, "priv/protos")

  # Register all proto files as external resources for recompilation tracking
  @proto_files Path.wildcard(Path.join(@protos_dir, "*.proto"))

  for file <- @proto_files do
    @external_resource file
  end

  @pages @proto_files
         |> Enum.map(fn file ->
           content = File.read!(file)
           parsed = ProtoParser.parse(content)
           service_name = ProtoParser.display_name(parsed)
           id = file |> Path.basename(".proto") |> String.replace("micelio_", "")

           %Micelio.Docs.Page{
             id: id,
             title: service_name,
             description: "gRPC API reference for the #{service_name} service.",
             category: "grpc",
             body: ProtoParser.render_html(parsed)
           }
         end)
         |> Enum.sort_by(& &1.id)

  @doc """
  Returns all generated gRPC documentation pages.
  """
  def pages, do: @pages

  @doc """
  Returns a single page by ID, or nil.
  """
  def get_page(id) do
    Enum.find(@pages, &(&1.id == id))
  end
end
