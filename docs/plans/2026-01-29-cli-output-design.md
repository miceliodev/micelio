# CLI Output Formatting Design (Mic CLI)

Date: 2026-01-29

## Goals

- Provide consistent CLI output with three channels: errors, warnings, and success.
- Accumulate warnings during execution; errors abort the command.
- Support rich formatting when the terminal supports it and the user has not opted out.
- Default output is human-readable; support JSON output via `--json`.
- Keep output centralized in `main.zig` for uniform formatting and exit codes.

## Non-Goals

- Redesign command semantics beyond output and error handling.
- Capture or retroactively parse existing printed output; commands should migrate to structured output.

## Proposed Architecture

Introduce a small CLI output layer with structured types:

- `CLIReporter` collects warnings during execution.
- `CLIError` represents expected, user-facing errors and optional next steps.
- `CLISuccess` represents successful completion and optional details.
- `CLIResult` is a union of `success` or `error`.
- `CLIRenderer` formats output for rich/plain text or JSON.

Commands do not print directly. They return `CLIResult` and call `reporter.warn(...)` to add warnings. Unexpected Zig errors are allowed to bubble and are converted in `main` to a generic `CLIError`.

## Output Modes

- **JSON mode** (`--json`): emit a single JSON object.
- **Text mode** (default): human-readable.
- **Rich text**: enabled when output is a TTY and color is not disabled by env flags.

### Environment Variable Rules

Use common environment variables:

- `NO_COLOR` disables rich output.
- `FORCE_COLOR` enables rich output even if not TTY.
- `TERM=dumb` disables rich output.
- `CI` disables rich output.
- Optional override: `MIC_COLOR=auto|always|never`.

## JSON Schema

```json
{
  "status": "success|error",
  "warnings": [
    { "code": "...", "message": "...", "context": { "...": "..." } }
  ],
  "success": { "message": "...", "details": { "...": "..." } },
  "error": { "code": "...", "message": "...", "next_steps": [ "..." ] }
}
```

Only one of `success` or `error` is present. `warnings` is always present.

## Text Formatting

- Warnings section (if any): header + bullet list.
- Success: single line + optional details.
- Error: “Error:” line + next steps numbered list.

## Error Handling Strategy

- Expected errors: return `CLIError` with helpful `next_steps`.
- Unexpected errors: mapped in `main` to `CLIError` with `code = "internal_error"` and a single next step to re-run with debug or file an issue.

## Migration Plan

1. Add new CLI output module.
2. Update `main.zig` to create `CLIReporter`, detect output mode, and render.
3. Migrate critical commands (e.g., `session land`) to return `CLIResult` and avoid direct printing.
4. Gradually migrate remaining commands.

## Testing

- Unit tests for JSON output.
- Unit tests for rich/plain decision logic based on env variables.
- Integration test for a command that returns `CLIError` ensuring no Zig backtrace and correct exit code.
