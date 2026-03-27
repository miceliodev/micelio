defmodule Micelio.Docs.ProtoParser do
  @moduledoc """
  Parses .proto files and extracts services, RPCs, and messages with their comments.
  Also renders parsed proto data into HTML documentation.
  """

  defmodule Service do
    @moduledoc false
    defstruct [:name, :package, :comment, rpcs: []]
  end

  defmodule Rpc do
    @moduledoc false
    defstruct [:name, :input, :output, :comment]
  end

  defmodule Message do
    @moduledoc false
    defstruct [:name, :comment, fields: []]
  end

  defmodule Field do
    @moduledoc false
    defstruct [:name, :type, :number, :comment, repeated: false]
  end

  @doc """
  Parses a .proto file and returns a map with :package, :services, and :messages.
  """
  def parse(content) do
    lines = String.split(content, "\n")
    package = extract_package(lines)

    %{
      package: package,
      services: extract_services(lines),
      messages: extract_messages(lines)
    }
  end

  @doc """
  Returns the display name for a parsed proto (first service name or package).
  """
  def display_name(%{services: [service | _]}), do: service.name
  def display_name(%{package: pkg}) when is_binary(pkg), do: pkg
  def display_name(_), do: "Unknown Service"

  @doc """
  Renders a parsed proto into an HTML documentation string.
  """
  def render_html(%{package: package, services: services, messages: messages}) do
    [
      render_package_info(package),
      Enum.map(services, &render_service/1),
      render_messages_section(messages)
    ]
    |> List.flatten()
    |> Enum.join("\n")
  end

  # Parsing

  defp extract_package(lines) do
    Enum.find_value(lines, fn line ->
      case Regex.run(~r/^\s*package\s+(.+?)\s*;/, line) do
        [_, package] -> package
        _ -> nil
      end
    end)
  end

  defp extract_services(lines) do
    lines
    |> Enum.with_index()
    |> Enum.reduce([], fn {line, idx}, acc ->
      case Regex.run(~r/^\s*service\s+(\w+)\s*\{/, line) do
        [_, name] ->
          comment = collect_preceding_comments(lines, idx)
          rpcs = extract_rpcs(lines, idx)
          [%Service{name: name, comment: comment, rpcs: rpcs} | acc]

        _ ->
          acc
      end
    end)
    |> Enum.reverse()
  end

  defp extract_rpcs(lines, service_start_idx) do
    lines
    |> Enum.drop(service_start_idx + 1)
    |> Enum.with_index(service_start_idx + 1)
    |> Enum.reduce_while([], fn {line, idx}, acc ->
      cond do
        String.match?(line, ~r/^\s*\}/) ->
          {:halt, Enum.reverse(acc)}

        String.match?(line, ~r/^\s*rpc\s+/) ->
          case Regex.run(~r/^\s*rpc\s+(\w+)\s*\((\w+)\)\s*returns\s*\((\w+)\)/, line) do
            [_, name, input, output] ->
              comment = collect_preceding_comments(lines, idx)
              rpc = %Rpc{name: name, input: input, output: output, comment: comment}
              {:cont, [rpc | acc]}

            _ ->
              {:cont, acc}
          end

        true ->
          {:cont, acc}
      end
    end)
  end

  defp extract_messages(lines) do
    lines
    |> Enum.with_index()
    |> Enum.reduce([], fn {line, idx}, acc ->
      case Regex.run(~r/^\s*message\s+(\w+)\s*\{/, line) do
        [_, name] ->
          comment = collect_preceding_comments(lines, idx)
          fields = extract_fields(lines, idx)
          [%Message{name: name, comment: comment, fields: fields} | acc]

        _ ->
          acc
      end
    end)
    |> Enum.reverse()
  end

  defp extract_fields(lines, message_start_idx) do
    lines
    |> Enum.drop(message_start_idx + 1)
    |> Enum.with_index(message_start_idx + 1)
    |> Enum.reduce_while([], fn {line, idx}, acc ->
      cond do
        String.match?(line, ~r/^\s*\}/) ->
          {:halt, Enum.reverse(acc)}

        String.match?(line, ~r/^\s*reserved\s+/) ->
          {:cont, acc}

        String.match?(line, ~r/^\s*(repeated\s+)?(\w+(\.\w+)*)\s+(\w+)\s*=\s*(\d+)/) ->
          case Regex.run(
                 ~r/^\s*(repeated\s+)?(\w+(?:\.\w+)*)\s+(\w+)\s*=\s*(\d+)/,
                 line
               ) do
            [_, repeated, type, name, number] ->
              comment = collect_preceding_comments(lines, idx)

              inline_comment =
                case Regex.run(~r/\/\/\s*(.+)$/, line) do
                  [_, c] -> c
                  _ -> nil
                end

              field = %Field{
                name: name,
                type: type,
                number: String.to_integer(number),
                repeated: repeated != "",
                comment: inline_comment || comment
              }

              {:cont, [field | acc]}

            _ ->
              {:cont, acc}
          end

        true ->
          {:cont, acc}
      end
    end)
  end

  defp collect_preceding_comments(lines, idx) do
    lines
    |> Enum.take(idx)
    |> Enum.reverse()
    |> Enum.take_while(fn line ->
      trimmed = String.trim(line)
      String.starts_with?(trimmed, "//") or trimmed == ""
    end)
    |> Enum.reject(&(String.trim(&1) == ""))
    |> Enum.reverse()
    |> Enum.map_join(" ", fn line ->
      line
      |> String.trim()
      |> String.replace_leading("// ", "")
      |> String.replace_leading("//", "")
    end)
    |> case do
      "" -> nil
      comment -> comment
    end
  end

  # Rendering

  defp render_package_info(nil), do: []

  defp render_package_info(package) do
    [~s(<p class="grpc-doc-package">Package: <code>#{escape(package)}</code></p>\n)]
  end

  defp render_service(service) do
    rpcs_html =
      service.rpcs
      |> Enum.map_join("\n", &render_rpc/1)

    comment_html =
      if service.comment do
        ~s(<p class="grpc-doc-comment">#{escape(service.comment)}</p>\n)
      else
        ""
      end

    """
    <h2>#{escape(service.name)}</h2>
    #{comment_html}
    <div class="grpc-doc-table-wrapper">
    <table class="grpc-doc-table">
    <thead>
    <tr><th>RPC</th><th>Request</th><th>Response</th><th>Description</th></tr>
    </thead>
    <tbody>
    #{rpcs_html}
    </tbody>
    </table>
    </div>
    """
  end

  defp render_rpc(rpc) do
    comment = if rpc.comment, do: escape(rpc.comment), else: ""

    """
    <tr>
    <td><code>#{escape(rpc.name)}</code></td>
    <td><code>#{escape(rpc.input)}</code></td>
    <td><code>#{escape(rpc.output)}</code></td>
    <td>#{comment}</td>
    </tr>
    """
  end

  defp render_messages_section([]), do: []

  defp render_messages_section(messages) do
    messages_html = Enum.map(messages, &render_message/1) |> Enum.join("\n")

    [
      "<h2>Messages</h2>\n",
      messages_html
    ]
  end

  defp render_message(message) do
    comment_html =
      if message.comment do
        ~s(<p class="grpc-doc-comment">#{escape(message.comment)}</p>\n)
      else
        ""
      end

    fields_html =
      if message.fields == [] do
        ~s(<p class="grpc-doc-empty">No fields.</p>)
      else
        rows = Enum.map(message.fields, &render_field/1) |> Enum.join("\n")

        """
        <div class="grpc-doc-table-wrapper">
        <table class="grpc-doc-table">
        <thead>
        <tr><th>Field</th><th>Type</th><th>Number</th><th>Description</th></tr>
        </thead>
        <tbody>
        #{rows}
        </tbody>
        </table>
        </div>
        """
      end

    """
    <h3><code>#{escape(message.name)}</code></h3>
    #{comment_html}
    #{fields_html}
    """
  end

  defp render_field(field) do
    type_display = if field.repeated, do: "repeated #{field.type}", else: field.type
    comment = if field.comment, do: escape(field.comment), else: ""

    """
    <tr>
    <td><code>#{escape(field.name)}</code></td>
    <td><code>#{escape(type_display)}</code></td>
    <td>#{field.number}</td>
    <td>#{comment}</td>
    </tr>
    """
  end

  defp escape(text) do
    text
    |> String.replace("&", "&amp;")
    |> String.replace("<", "&lt;")
    |> String.replace(">", "&gt;")
    |> String.replace("\"", "&quot;")
  end
end
