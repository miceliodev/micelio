defmodule Micelio.Protocol.VirtualVcsContractTest do
  use ExUnit.Case, async: true

  alias Micelio.Docs.ProtoParser

  @proto_path Path.expand("../../../build/protocols/micelio_virtual_vcs_v1.proto", __DIR__)
  @compatibility_path Path.expand(
    "../../../build/protocols/micelio_virtual_vcs_v1.compatibility.md",
    __DIR__
  )

  describe "virtual_v1 protocol contract" do
    test "services and RPC names are frozen" do
      parsed = parsed_proto()

      assert parsed.package == "micelio.virtual.v1"

      versioning_rpcs = service_rpcs(parsed, "VersioningService")
      content_rpcs = service_rpcs(parsed, "ContentService")
      search_rpcs = service_rpcs(parsed, "SearchService")

      assert MapSet.new(versioning_rpcs) ==
               MapSet.new([
                 "GetRepositoryHead",
                 "GetHeadAt",
                 "OpenSession",
                 "AppendSessionConversation",
                 "AppendSessionChange",
                 "LandSession",
                 "AbandonSession",
                 "GetSession"
               ])

      assert MapSet.new(content_rpcs) == MapSet.new(["GetTree", "GetPath", "GetBlob", "Diff", "Blame"])
      assert MapSet.new(search_rpcs) == MapSet.new(["QueryText"])
      assert String.contains?(File.read!(@compatibility_path), "Legacy RPC")
    end

    test "required and optional field annotations are present" do
      parsed = parsed_proto()

      required_fields = [
        {"RepositoryRef", "organization_handle", "REQUIRED"},
        {"RepositoryRef", "repository_handle", "REQUIRED"},
        {"GetRepositoryHeadRequest", "user_id", "REQUIRED"},
        {"GetRepositoryHeadRequest", "repository", "REQUIRED"},
        {"SessionOpen", "session_id", "REQUIRED"},
        {"SessionOpen", "goal", "REQUIRED"},
        {"SessionOpenRequest", "user_id", "REQUIRED"},
        {"SessionOpenRequest", "repository", "REQUIRED"},
        {"LandSessionRequest", "user_id", "REQUIRED"},
        {"LandSessionRequest", "session_id", "REQUIRED"},
        {"LandSessionRequest", "finalize", "REQUIRED"}
      ]

      for {message_name, field_name, marker} <- required_fields do
        assert has_field_comment?(parsed, message_name, field_name, marker),
               "Expected #{message_name}.#{field_name} to include #{marker}"
      end

      optional_fields = [
        {"SessionOpen", "requested_workspace", "OPTIONAL"},
        {"SessionInfo", "conversation", "OPTIONAL"},
        {"SessionInfo", "decisions", "OPTIONAL"},
        {"TextQueryResponse", "next_page_token", "OPTIONAL"},
        {"TextQueryRequest", "page_token", "OPTIONAL"}
      ]

      for {message_name, field_name, marker} <- optional_fields do
        assert has_field_comment?(parsed, message_name, field_name, marker),
               "Expected #{message_name}.#{field_name} to include #{marker}"
      end
    end

    test "search response shape supports pagination contracts" do
      parsed = parsed_proto()

      assert has_field?(parsed, "TextQueryResponse", "total")
      assert has_field?(parsed, "TextQueryResponse", "matches")
      assert has_field?(parsed, "TextQueryResponse", "next_page_token")

      assert has_field?(parsed, "TextQueryRequest", "query")
      assert has_field?(parsed, "TextQueryRequest", "limit")
      assert has_field?(parsed, "TextQueryRequest", "page_token")
    end

    test "landing conflict payload exists and is explicitly modeled" do
      parsed = parsed_proto()

      assert has_message?(parsed, "SessionConflict")
      assert has_field?(parsed, "SessionInfo", "conflict")
      assert has_field?(parsed, "SessionConflict", "position")
      assert has_field?(parsed, "SessionConflict", "reason")
    end
  end

  defp parsed_proto do
    @proto_path
    |> File.read!()
    |> ProtoParser.parse()
  end

  defp service_rpcs(parsed, service_name) do
    parsed.services
    |> Enum.find(fn service -> service.name == service_name end)
    |> then(& &1.rpcs)
    |> Enum.map(& &1.name)
  end

  defp has_message?(parsed, message_name) do
    Enum.any?(parsed.messages, &(&1.name == message_name))
  end

  defp has_field?(parsed, message_name, field_name) do
    parsed
    |> find_message_fields(message_name)
    |> Enum.any?(fn %ProtoParser.Field{name: name} -> name == field_name end)
  end

  defp has_field_comment?(parsed, message_name, field_name, marker) do
    parsed
    |> find_message_fields(message_name)
    |> Enum.find_value(fn
      %ProtoParser.Field{name: ^field_name, comment: comment} when is_binary(comment) ->
        String.contains?(comment, marker)

      _ ->
        false
    end)
  end

  defp find_message_fields(parsed, message_name) do
    case Enum.find(parsed.messages, &(&1.name == message_name)) do
      nil -> []
      %ProtoParser.Message{fields: fields} -> fields
    end
  end
end
