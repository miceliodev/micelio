---
title: "feat: Add status filter tabs to prompt-requests list"
type: feat
date: 2026-02-19
---

# Add status filter tabs to prompt-requests list

Add filter tabs (Open, Closed, All) with counts to the prompt-requests list page, following the established pattern from `SessionLive.Index`.

## Acceptance Criteria

- [x]Filter bar with three tabs: Open (default), Closed, All
- [x]Each tab shows the count of plans in that status
- [x]Clicking a tab reloads the list to show only matching plans
- [x]"All" disables filtering and shows all plans
- [x]Empty state message adapts to the selected filter
- [x]Styling follows the sessions filter bar pattern
- [x]All new strings wrapped in `gettext()`

## Context

**Pattern to follow:** `lib/micelio_web/live/session_live/index.ex` (lines 45-78 for event handling, lines 117-197 for template markup)

**Plan statuses:** `"open"` and `"closed"` (validated in `Plan.status_changeset/2`)

**Current state:** `list_plans_for_repository/2` already accepts `status` option (defaults to `"open"`). The `count_plans_for_repository/1` exists but doesn't filter by status.

## MVP

### 1. `lib/micelio/plans.ex` - Add count-by-status function and support "all" filter

Add a function to get counts grouped by status in a single query:

```elixir
def count_plans_by_status(repository) do
  Plan
  |> where([plan], plan.repository_id == ^repository.id)
  |> group_by([plan], plan.status)
  |> select([plan], {plan.status, count(plan.id)})
  |> Repo.all()
  |> Map.new()
end
```

Update `list_plans_for_repository/2` to handle `nil` status (for "all"):

```elixir
def list_plans_for_repository(repository, opts \\ []) do
  status = Keyword.get(opts, :status, "open")

  Plan
  |> where([plan], plan.repository_id == ^repository.id)
  |> maybe_filter_status(status)
  |> order_by([plan], desc: plan.number, desc: plan.inserted_at)
  |> preload(:user)
  |> Repo.all()
end

defp maybe_filter_status(query, nil), do: query
defp maybe_filter_status(query, status), do: where(query, [plan], plan.status == ^status)
```

### 2. `lib/micelio_web/live/plan_live/index.ex` - Add filter state and event handler

In `mount/3`, initialize `status_filter` and use `load_plans/1` helper:

```elixir
socket
|> assign(:status_filter, "open")
|> load_plans()
```

Add event handler and helpers (same pattern as sessions):

```elixir
def handle_event("filter", %{"status" => status}, socket) do
  {:noreply, socket |> assign(:status_filter, status) |> load_plans()}
end

defp load_plans(socket) do
  repository = socket.assigns.repository
  status_filter = socket.assigns.status_filter

  opts = [] |> maybe_put(:status, status_filter)
  plans = Plans.list_plans_for_repository(repository, opts)
  counts = Plans.count_plans_by_status(repository)

  socket
  |> assign(:plans, plans)
  |> assign(:plan_counts, counts)
end

defp maybe_put(opts, _key, "all"), do: opts
defp maybe_put(opts, key, value), do: Keyword.put(opts, key, value)
```

Update template toolbar to replace the static count with filter buttons:

```heex
<div class="plans-filter-bar">
  <button type="button"
    class={["plans-filter-btn", @status_filter == "open" && "is-active"]}
    phx-click="filter" phx-value-status="open">
    <!-- open icon (speech bubble) -->
    {gettext("Open")}
    <span class="plans-filter-count">{Map.get(@plan_counts, "open", 0)}</span>
  </button>
  <button type="button"
    class={["plans-filter-btn", @status_filter == "closed" && "is-active"]}
    phx-click="filter" phx-value-status="closed">
    <!-- closed icon (checkmark) -->
    {gettext("Closed")}
    <span class="plans-filter-count">{Map.get(@plan_counts, "closed", 0)}</span>
  </button>
  <button type="button"
    class={["plans-filter-btn", @status_filter == "all" && "is-active"]}
    phx-click="filter" phx-value-status="all">
    {gettext("All")}
    <span class="plans-filter-count">{total_count(@plan_counts)}</span>
  </button>
</div>
```

Add helper:

```elixir
defp total_count(counts) do
  counts |> Map.values() |> Enum.sum()
end
```

Update empty state message to be filter-aware:

```elixir
defp empty_message("open"), do: gettext("There aren't any open plans.")
defp empty_message("closed"), do: gettext("There aren't any closed plans.")
defp empty_message(_), do: gettext("There aren't any plans.")
```

### 3. `assets/css/routes/plans.css` - Add filter bar styles

Adapt from `assets/css/routes/sessions.css` (lines 35-83), using `plans-` prefix:

```css
.plans-filter-bar {
  display: flex;
  align-items: center;
  gap: var(--theme-ui-space-2);
}

.plans-filter-btn {
  display: inline-flex;
  align-items: center;
  gap: 4px;
  padding: 4px 8px;
  font-size: var(--theme-ui-font-size-sm);
  color: var(--theme-ui-colors-muted);
  background: none;
  border: none;
  border-radius: var(--theme-ui-radii-default);
  cursor: pointer;
  transition: color 0.1s ease;
}

.plans-filter-btn:hover {
  color: var(--theme-ui-colors-text);
}

.plans-filter-btn.is-active {
  color: var(--theme-ui-colors-text);
  font-weight: var(--theme-ui-font-weights-semibold);
}

.plans-filter-icon {
  width: 14px;
  height: 14px;
  flex-shrink: 0;
}

.plans-filter-count {
  font-size: var(--theme-ui-font-size-xs);
  background-color: var(--theme-ui-colors-border);
  padding: 0 6px;
  border-radius: 999px;
  min-width: 18px;
  text-align: center;
  line-height: 1.6;
}
```

### 4. i18n - Extract and merge translations

```bash
mix gettext.extract
mix gettext.merge priv/gettext
```

New strings to translate: "Open", "Closed", "All", "There aren't any closed plans.", "There aren't any plans."

## Design Decisions

- **No URL persistence:** Filter resets to "open" on page reload (matches sessions behavior)
- **No sort dropdown:** Keep scope minimal; can be added later
- **Single aggregation query** for counts: efficient even at scale
- **Default to "open":** Matches current behavior and user expectation

## References

- Session filter pattern: `lib/micelio_web/live/session_live/index.ex`
- Session filter CSS: `assets/css/routes/sessions.css:35-83`
- Plans context: `lib/micelio/plans.ex:487-516`
- Plan schema status: `lib/micelio/plans/plan.ex:32`
