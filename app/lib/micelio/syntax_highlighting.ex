defmodule Micelio.SyntaxHighlighting do
  @moduledoc """
  Registers convenient aliases for syntax highlighting languages.

  makeup_syntect uses verbose codeblock names like `bourne_again_shell_bash`.
  This module registers shorter, more common aliases like `bash` and `sh`.

  This module uses @before_compile to ensure aliases are registered before
  any NimblePublisher modules are compiled.
  """

  @doc """
  Registers syntax highlighting language aliases.

  This should be called early in the application startup, or at compile time
  for NimblePublisher to pick up the aliases.
  """
  def register_aliases do
    # Ensure makeup_syntect application is started so its lexers are registered
    Application.ensure_all_started(:makeup)
    Application.ensure_all_started(:makeup_syntect)

    # bash/shell aliases
    register_alias("bash", "Bourne Again Shell (bash)")
    register_alias("sh", "Bourne Again Shell (bash)")
    register_alias("shell", "Bourne Again Shell (bash)")
    register_alias("zsh", "Bourne Again Shell (bash)")

    # YAML aliases
    register_alias("yaml", "YAML")
    register_alias("yml", "YAML")

    # JSON aliases
    register_alias("json", "JSON")

    # JavaScript aliases
    register_alias("javascript", "JavaScript")
    register_alias("js", "JavaScript")

    # TypeScript aliases
    register_alias("typescript", "TypeScript")
    register_alias("ts", "TypeScript")

    # Ruby alias
    register_alias("ruby", "Ruby")
    register_alias("rb", "Ruby")

    # Python alias
    register_alias("python", "Python")
    register_alias("py", "Python")

    # SQL alias
    register_alias("sql", "SQL")

    # Markdown alias
    register_alias("markdown", "Markdown")
    register_alias("md", "Markdown")

    # CSS alias
    register_alias("css", "CSS")

    # HTML alias
    register_alias("html", "HTML")

    # TOML alias
    register_alias("toml", "TOML")

    # Dockerfile alias
    register_alias("dockerfile", "Dockerfile")

    # Makefile alias
    register_alias("makefile", "Makefile")
    register_alias("make", "Makefile")

    :ok
  end

  defp register_alias(alias_name, language_name) do
    # Only register if makeup_syntect is available and the language exists
    if Code.ensure_loaded?(MakeupSyntect.Lexer) do
      Makeup.Registry.register_lexer(
        MakeupSyntect.Lexer,
        options: [language: language_name],
        names: [alias_name],
        extensions: []
      )
    end
  rescue
    # Ignore errors if the language doesn't exist
    _ -> :ok
  end
end

# Register aliases at compile time so NimblePublisher can use them.
# This runs when this module is compiled, which must happen before
# any module that uses NimblePublisher.
Micelio.SyntaxHighlighting.register_aliases()
