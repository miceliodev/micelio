# CLI Output Formatting Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add a structured CLI output system (errors, warnings, success) with rich/plain/JSON rendering and use it to avoid backtraces for expected errors.

**Architecture:** Introduce `CLIReporter`, `CLIError`, `CLISuccess`, `CLIResult`, and `CLIRenderer` in a new module. `main.zig` decides output mode (`--json` and env/TTY checks), renders warnings + success/error, and exits with the correct code. Start by migrating `mic session land` to return `CLIResult` and use the renderer.

**Tech Stack:** Zig 0.15, yazap CLI parser.

### Task 1: Add failing tests for CLI output mode and JSON rendering

**Files:**
- Create: `mic/src/cli_output.zig`
- Test: `mic/src/cli_output.zig`

**Step 1: Write the failing test**

```zig
const std = @import("std");

const cli = @import("cli_output.zig");

test "color preference honors env flags" {
    const env = cli.EnvFlags{
        .mic_color = "auto",
        .no_color = true,
        .force_color = false,
        .term = "xterm-256color",
        .ci = false,
    };

    const mode = cli.colorModeFor(env, true);
    try std.testing.expectEqual(cli.ColorMode.plain, mode);
}

test "json renderer emits warnings and success" {
    const allocator = std.testing.allocator;
    var reporter = cli.CLIReporter.init(allocator);
    defer reporter.deinit();

    try reporter.warn(.{ .code = "warn", .message = "Heads up" });

    const result = cli.CLIResult{
        .success = .{ .message = "OK", .details = null },
    };

    const rendered = try cli.renderJson(allocator, reporter.warnings(), result);
    defer allocator.free(rendered);

    try std.testing.expect(std.mem.indexOf(u8, rendered, "\"warnings\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, rendered, "\"status\":\"success\"") != null);
}
```

**Step 2: Run test to verify it fails**

Run: `cd mic && zig build test`
Expected: FAIL because `cli_output.zig` does not provide required types/functions.

**Step 3: Write minimal implementation**

Create `cli_output.zig` with:
- `EnvFlags` struct
- `ColorMode` enum
- `colorModeFor(env: EnvFlags, is_tty: bool) ColorMode`
- `CLIWarning`, `CLIReporter` (collect warnings)
- `CLIError`, `CLISuccess`, `CLIResult`
- `renderJson(allocator, warnings, result) ![]u8`

**Step 4: Run test to verify it passes**

Run: `cd mic && zig build test`
Expected: PASS for the new tests.

**Step 5: Commit**

```bash
git add mic/src/cli_output.zig
git commit -m "feat: add CLI output types and JSON renderer"
```

### Task 2: Add output mode detection and text renderer

**Files:**
- Modify: `mic/src/cli_output.zig`

**Step 1: Write the failing test**

```zig
test "color preference honors FORCE_COLOR and TERM=dumb" {
    const env_force = cli.EnvFlags{ .mic_color = "auto", .no_color = false, .force_color = true, .term = "dumb", .ci = true };
    const env_dumb = cli.EnvFlags{ .mic_color = "auto", .no_color = false, .force_color = false, .term = "dumb", .ci = false };

    try std.testing.expectEqual(cli.ColorMode.rich, cli.colorModeFor(env_force, false));
    try std.testing.expectEqual(cli.ColorMode.plain, cli.colorModeFor(env_dumb, true));
}
```

**Step 2: Run test to verify it fails**

Run: `cd mic && zig build test`
Expected: FAIL if logic not implemented.

**Step 3: Write minimal implementation**

Add:
- `CLIRenderer` with `renderText(...)` and `render(...)` helpers
- Use ANSI when mode is rich; otherwise plain text
- Warnings rendered before success/error

**Step 4: Run test to verify it passes**

Run: `cd mic && zig build test`
Expected: PASS.

**Step 5: Commit**

```bash
git add mic/src/cli_output.zig
git commit -m "feat: add text renderer and color mode detection"
```

### Task 3: Wire `--json` and CLI output into `main.zig`

**Files:**
- Modify: `mic/src/main.zig`

**Step 1: Write the failing test**

```zig
test "main renders CLIError without backtrace" {
    _ = @import("main.zig");
}
```

**Step 2: Run test to verify it fails**

Run: `cd mic && zig build test`
Expected: FAIL due to missing output wiring.

**Step 3: Write minimal implementation**

- Add `--json` flag at root.
- Introduce `run(...) !CLIResult` that executes command routing.
- `main()` becomes `void`, calls `run`, renders output, and exits with correct code.
- `main` determines rich/plain by checking env vars + TTY and uses `CLIReporter`.

**Step 4: Run test to verify it passes**

Run: `cd mic && zig build test`
Expected: PASS.

**Step 5: Commit**

```bash
git add mic/src/main.zig
git commit -m "feat: render CLI output with json and color detection"
```

### Task 4: Migrate `session land` to structured output

**Files:**
- Modify: `mic/src/session.zig`
- Modify: `mic/src/main.zig`

**Step 1: Write the failing test**

```zig
test "session land returns CLIError when no active session" {
    const allocator = std.testing.allocator;
    var reporter = cli.CLIReporter.init(allocator);
    defer reporter.deinit();

    const result = try session.land(allocator, "http://localhost:50051", &reporter);
    switch (result) {
        .error => |err| try std.testing.expectEqualStrings("no_active_session", err.code),
        else => return error.TestExpectedEqual,
    }
}
```

**Step 2: Run test to verify it fails**

Run: `cd mic && zig build test`
Expected: FAIL because `session.land` signature and error handling are not updated.

**Step 3: Write minimal implementation**

- Change `session.land` to return `CLIResult` and accept `*CLIReporter`.
- Map `No active session` into `CLIError` with next steps (e.g., `mic session start ...`).
- Remove direct `std.debug.print` in `session.land` for errors/success.
- Update `main` to use new signature for `session land` command only.

**Step 4: Run test to verify it passes**

Run: `cd mic && zig build test`
Expected: PASS.

**Step 5: Commit**

```bash
git add mic/src/session.zig mic/src/main.zig
git commit -m "feat: return structured CLI result for session land"
```
