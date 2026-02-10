# Architecture Refactoring Plan

**Date**: 2026-01-18  
**Reviewer**: Distinguished Elixir & Zig Engineer  
**Status**: Active

---

## Executive Summary

This document outlines architectural improvements for the Micelio codebase to enable parallel test execution and improve long-term maintainability. The primary blockers are **global state via `Application.put_env`** and **SQLite's single-writer constraint**.

---

## Critical Issues Found

### 1. Global State in Tests (HIGH PRIORITY)

**Problem**: Multiple test files modify global application configuration via `Application.put_env/get_env`, which creates race conditions when tests run in parallel.

**Affected Files**:
- `test/micelio/storage_test.exs`
- `test/micelio/storage/s3_test.exs`
- `test/micelio/mic/delta_compression_test.exs`
- `test/micelio/mic/seed_test.exs`
- `test/micelio/mic/rollup_worker_test.exs`
- `test/micelio/mic/landing_workflow_test.exs`
- `test/micelio_web/controllers/browser/project_controller_test.exs`
- `test/micelio/projects_workspace_test.exs`

**Current Pattern** (anti-pattern):
```elixir
setup do
  previous = Application.get_env(:micelio, Micelio.Storage)
  Application.put_env(:micelio, Micelio.Storage, backend: :local, local_path: storage_dir)
  
  on_exit(fn ->
    Application.put_env(:micelio, Micelio.Storage, previous)
  end)
end
```

### 2. Mimic with `set_mimic_global` 

**Problem**: Tests using `:set_mimic_global` mode cannot run concurrently because mocks are shared across all processes.

**Affected Files**:
- `test/micelio/storage_test.exs`
- `test/micelio/webhooks_test.exs`
- `test/micelio/storage/s3_test.exs`
- `test/micelio/storage/tiered_test.exs`
- `test/micelio/grpc/sessions_workflow_test.exs`
- `test/micelio/grpc/sessions_server_test.exs`
- `test/micelio/theme_generator_llm_test.exs`

### 3. SQLite Single-Writer Constraint

**Problem**: SQLite only allows one writer at a time, forcing `max_cases: 1` in test configuration.

**Current Mitigation**: Test partitioning via `MIX_TEST_PARTITION` (each partition uses separate DB file).

---

## Recommended Solutions

### Phase 1: Dependency Injection for Storage (Week 1-2)

**Goal**: Replace global config reads with explicit dependency injection.

**Step 1.1**: Modify `Micelio.Storage` to accept optional config override

```elixir
# lib/micelio/storage.ex

defmodule Micelio.Storage do
  @moduledoc """
  Storage abstraction with optional per-call configuration override.
  """

  @doc """
  Store a file. Accepts optional `opts[:config]` to override default config.
  """
  def put(key, content, opts \\ []) do
    backend(opts).put(key, content)
  end

  def get(key, opts \\ []) do
    backend(opts).get(key)
  end
  
  # ... other functions

  defp backend(opts) do
    config = Keyword.get(opts, :config) || Application.get_env(:micelio, __MODULE__, [])
    backend_type = Keyword.get(config, :backend, :local)

    case backend_type do
      :local -> {Micelio.Storage.Local, config}
      :s3 -> {Micelio.Storage.S3, config}
      :tiered -> {Micelio.Storage.Tiered, config}
    end
    |> elem(0)
  end
end
```

**Step 1.2**: Create test helper for storage config

```elixir
# test/support/storage_helper.ex

defmodule Micelio.StorageHelper do
  @doc """
  Creates an isolated storage configuration for a test.
  Returns config keyword list that can be passed to Storage functions.
  """
  def isolated_storage_config(opts \\ []) do
    unique = System.unique_integer([:positive])
    base_dir = Keyword.get(opts, :base_dir, System.tmp_dir!())
    storage_dir = Path.join([base_dir, "micelio-test-#{unique}", "storage"])
    File.mkdir_p!(storage_dir)
    
    [backend: :local, local_path: storage_dir]
  end
  
  @doc """
  Cleans up a storage directory.
  """
  def cleanup_storage(config) do
    if path = Keyword.get(config, :local_path) do
      File.rm_rf!(Path.dirname(path))
    end
  end
end
```

**Step 1.3**: Update tests to use isolated config

```elixir
# test/micelio/mic/landing_workflow_test.exs (refactored)

defmodule Micelio.Mic.LandingWorkflowTest do
  use Micelio.DataCase, async: true  # Now can be async!
  
  alias Micelio.StorageHelper

  setup do
    config = StorageHelper.isolated_storage_config()
    
    on_exit(fn ->
      StorageHelper.cleanup_storage(config)
    end)

    {:ok, storage_config: config}
  end

  test "lands a session end-to-end", %{storage_config: config} do
    # Pass config to functions that need storage
    # ...
  end
end
```

### Phase 2: Process Dictionary for Test Context (Deprecated)

**Do not use this approach.** Process dictionary configuration is global state and
is not allowed in tests. Use explicit opts injection instead.

### Phase 3: Mimic Private Mode (Week 3)

**Goal**: Convert tests from `set_mimic_global` to `set_mimic_private` where possible.

**Requirement**: Tests must own the process that calls the mocked function.

For most tests, this means using `set_mimic_private` in `setup` instead of `setup_all`:

```elixir
# Before (global mode - blocks parallelization)
setup :set_mimic_global
setup_all do
  Mimic.copy(Req)
  :ok
end

# After (private mode - allows parallelization)
setup :set_mimic_private
setup do
  Mimic.copy(Req)
  :ok
end
```

**Note**: Some tests genuinely need global mode (e.g., when spawned processes call mocked functions). These should stay `async: false`.

### Phase 4: PostgreSQL Option for Development/CI (Week 4+)

**Goal**: Add PostgreSQL support for true parallel test execution.

**Benefits**:
- True async database tests
- Better CI parallelization
- More production-like testing

**Migration Steps**:
1. Add `postgrex` dependency
2. Create Postgres-specific config
3. Update migrations for Postgres compatibility
4. CI matrix with both SQLite and Postgres

---

## Module Organization Review

### Strengths ✓

1. **Context boundaries well-defined**: `Accounts`, `Projects`, `Sessions`, `Storage`, `OAuth`, `GRPC`
2. **Consistent naming**: Follows Phoenix conventions
3. **Schema design**: Proper use of Ecto schemas with changesets
4. **LiveView organization**: Clean separation between LiveViews and components

### Minor Improvements

#### 1. Extract Common Patterns

**Current**: Duplicate storage setup in multiple Mic modules

```elixir
# Found in: seed.ex, landing.ex, project.ex
"projects/#{project_id}/..."
```

**Recommendation**: Extract to `Micelio.Mic.StorageKeys`

```elixir
defmodule Micelio.Mic.StorageKeys do
  def project_prefix(project_id), do: "projects/#{project_id}"
  def landing_key(project_id, position), do: "#{project_prefix(project_id)}/landing/#{pad(position)}.bin"
  def session_key(project_id, session_id), do: "#{project_prefix(project_id)}/sessions/#{session_id}.bin"
  def blob_key(project_id, hash), do: "#{project_prefix(project_id)}/blobs/#{hash}"
  def tree_key(project_id, hash), do: "#{project_prefix(project_id)}/trees/#{hash}.json"
  
  defp pad(n), do: n |> Integer.to_string() |> String.pad_leading(12, "0")
end
```

#### 2. Consider Protocol for Storage Backends

**Current**: Pattern matching on backend type in `Micelio.Storage`

**Recommendation**: Use behaviour/protocol for cleaner extension

```elixir
defmodule Micelio.Storage.Backend do
  @callback put(key :: String.t(), content :: binary()) :: {:ok, String.t()} | {:error, term()}
  @callback get(key :: String.t()) :: {:ok, binary()} | {:error, term()}
  @callback delete(key :: String.t()) :: :ok | {:error, term()}
  @callback list(prefix :: String.t()) :: {:ok, [String.t()]} | {:error, term()}
  @callback exists?(key :: String.t()) :: boolean()
end
```

---

## Zig Code Review

### Strengths ✓

1. **Memory management**: Proper `defer` patterns throughout
2. **Error handling**: Idiomatic error unions
3. **Documentation**: Excellent docstrings in `tree.zig`
4. **Test coverage**: Comprehensive unit tests

### Minor Recommendations

#### 1. Consider Comptime for Hash Size

```zig
// Current
const HASH_SIZE = hash_mod.HASH_SIZE;

// Could be comptime-verified
const HASH_SIZE = comptime blk: {
    break :blk @typeInfo(Hash).Array.len;
};
```

#### 2. Add `arena` Parameter Pattern

The codebase already uses ArenaAllocator in some places. Consider making this more consistent:

```zig
// For functions doing many small allocations
pub fn processRequest(arena: *std.heap.ArenaAllocator, ...) !Result {
    const allocator = arena.allocator();
    // All allocations freed when arena is reset
}
```

---

## Test Parallelization Checklist

### Files Ready for `async: true` After Refactoring

- [ ] `test/micelio/mic/seed_test.exs` (after Phase 1)
- [ ] `test/micelio/mic/landing_workflow_test.exs` (after Phase 1)
- [ ] `test/micelio/mic/rollup_worker_test.exs` (after Phase 1)
- [ ] `test/micelio/mic/delta_compression_test.exs` (after Phase 1)
- [ ] `test/micelio/projects_workspace_test.exs` (after Phase 1)
- [ ] `test/micelio/storage_test.exs` (after Phase 1 + 3)
- [ ] `test/micelio/storage/s3_test.exs` (after Phase 3)
- [ ] `test/micelio/storage/tiered_test.exs` (after Phase 3)

### Files Requiring `async: false` (Legitimate)

- `test/micelio/grpc/auth_required_test.exs` - Tests global auth state
- Tests using `setup_all` with external resources

---

## Immediate Quick Wins (Applied)

1. ✓ Fixed deprecation warning: `Phoenix.Controller.get_flash/2` → `Phoenix.Flash.get/2`
2. ✓ Updated test_helper.exs comments for clarity
3. ✓ Created this refactoring plan

---

## Priority Order

1. **Week 1**: Phase 1 - Storage dependency injection
2. **Week 2**: Continue Phase 1 + Start Phase 2  
3. **Week 3**: Phase 3 - Mimic private mode migration
4. **Week 4+**: Phase 4 - PostgreSQL option (optional, based on team preference)

---

## Success Metrics

- Test suite runs with `max_cases: System.schedulers_online()` 
- No race conditions in CI
- Test duration reduced by 50%+ with parallelization
- All storage tests run with `async: true`
