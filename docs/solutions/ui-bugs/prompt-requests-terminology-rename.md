---
title: Resolve Gettext Merge Conflicts After Terminology Rename
date: 2026-02-19
category: ui-bugs
tags:
  - gettext
  - merge-conflicts
  - i18n
  - terminology
  - elixir
  - phoenix
severity: medium
component: Internationalization (priv/gettext)
symptoms:
  - User-facing strings say "plan/plans" while URLs use "prompt-requests"
  - Merge conflicts in default.pot and all locale .po files after renaming strings
resolution_time_minutes: 20
---

# Resolve Gettext Merge Conflicts After Terminology Rename

## Problem

URLs and navigation used "prompt-requests" but user-facing gettext strings still said "plan" or "plans" across 5 LiveView files. After fixing the strings and pushing, merge conflicts appeared in all 6 gettext files (default.pot + 5 locale .po files) when merging with main.

### Symptoms

- Inconsistent terminology between URL paths and UI labels
- `git merge origin/main` produces CONFLICT in every `priv/gettext/` file

## Root Cause

1. **Terminology drift**: URL refactoring (`/prs` to `/prompt-requests`) happened in an earlier commit, but gettext strings were not updated at the same time.
2. **Gettext merge conflicts**: `.pot`/`.po` files have timestamps, ordering, and fuzzy markers that change frequently. When both branches modify source files contributing gettext strings, the derived files conflict.

## Solution

### Pattern 1: Bulk Gettext String Rename

Only modify the string inside `gettext("...")` calls. Keep all internal code unchanged.

**What to change:**
```elixir
# Before
assign(socket, :page_title, gettext("Plans"))
put_flash(socket, :info, gettext("Plan created."))

# After
assign(socket, :page_title, gettext("Prompt requests"))
put_flash(socket, :info, gettext("Prompt request created."))
```

**What NOT to change:**
- Module names (`PlanLive`, `Plan`, `Plans`)
- Variable names (`@plan`, `@plans`, `plan_counts`)
- Function names (`list_plans_for_repository`, `load_plans`)
- CSS class names (`.plan-row`, `.plans-filter-btn`)
- Route atoms (`:plans`, `:prompt_requests`)

**After all edits, regenerate gettext atomically:**
```bash
mix compile --warnings-as-errors
mix gettext.extract && mix gettext.merge priv/gettext
```

### Pattern 2: Resolving Gettext Merge Conflicts

Gettext files are derived artifacts -- source `.ex` files are the truth. Don't manually resolve conflicts in `.pot`/`.po` files.

```bash
# 1. Accept the other branch's gettext files entirely
git checkout --theirs priv/gettext/default.pot \
  priv/gettext/en/LC_MESSAGES/default.po \
  priv/gettext/ja/LC_MESSAGES/default.po \
  priv/gettext/ko/LC_MESSAGES/default.po \
  priv/gettext/zh_CN/LC_MESSAGES/default.po \
  priv/gettext/zh_TW/LC_MESSAGES/default.po

# 2. Stage resolved files
git add priv/gettext/

# 3. Install any new deps from main (if needed)
mix deps.get

# 4. Regenerate from source (your branch has the correct strings)
mix gettext.extract && mix gettext.merge priv/gettext

# 5. Stage regenerated files and complete merge
git add priv/gettext/
git commit --no-edit
```

This works because `mix gettext.extract` scans your current branch's `.ex` files and rebuilds the `.pot` template from scratch, then `mix gettext.merge` updates all locale `.po` files to match.

## Prevention

### Keep Terminology Consistent
- When renaming URL paths, update gettext strings in the same commit
- Grep for the old term across all `gettext("...")` calls before considering the rename complete:
  ```bash
  grep -r 'gettext.*[Pp]lan' lib/micelio_web/live/plan_live/
  ```

### Minimize Gettext Merge Conflicts
- Never commit `.pot`/`.po` file changes separately from the source `.ex` changes that caused them
- Run `mix gettext.extract && mix gettext.merge priv/gettext` as the final step before committing, not as a separate commit
- On long-lived branches, regenerate gettext files right before merging

### Terminology Change Checklist
- [ ] All `gettext("...")` strings updated
- [ ] `mix compile --warnings-as-errors` passes
- [ ] `mix gettext.extract && mix gettext.merge priv/gettext` run
- [ ] Fuzzy translations reviewed in `.po` files
- [ ] No hardcoded English text remains (check with grep)

## Related

- `CLAUDE.md` "Internationalization (i18n)" section -- project gettext guidelines
- `CLAUDE.md` "Terminology" section -- standard terms like "repositories"
