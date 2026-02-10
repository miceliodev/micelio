defmodule MicelioWeb.CodeHighlighterTest do
  use ExUnit.Case, async: true

  alias MicelioWeb.CodeHighlighter

  test "highlights files with a registered lexer" do
    assert {:ok, highlighted} = CodeHighlighter.highlight("lib/app.ex", "IO.puts(\"ok\")\n")
    assert highlighted =~ "<span"
    assert highlighted =~ "ok"
  end

  test "returns no lexer for unknown extensions" do
    assert :no_lexer = CodeHighlighter.highlight("notes.unknownext", "Plain notes\n")
  end

  test "uses extension aliases for template files" do
    assert {:ok, highlighted} = CodeHighlighter.highlight("lib/app.heex", "IO.puts(\"ok\")\n")
    assert highlighted =~ "<span"
    assert highlighted =~ "ok"
  end
end
