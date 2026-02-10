%{
  title: "Code Style",
  description: "Coding conventions and style guidelines for Micelio contributions."
}
---

This guide covers the coding conventions used in Micelio.

## Elixir

### Syntax

- Lists **do not support index access**: Use `Enum.at/2`, pattern matching, or `List` functions
- Variables are immutable but can be rebound; block expressions must bind results
- **Never** nest multiple modules in the same file
- **Never** use map access (`changeset[:field]`) on structs
- Use standard library for dates: `Time`, `Date`, `DateTime`, `Calendar`
- Predicate functions end with `?` (not `is_`)

### Ecto

- **Never** use `@type` annotations in Ecto schema modules
- **Always** preload associations when accessed in templates
- Fields set programmatically must not be in `cast` calls
- **Always** use `mix ecto.gen.migration name` for migrations

### Phoenix

- Router `scope` blocks include an optional alias prefixed for all routes
- Don't use `Phoenix.View`

### HEEx Templates

- **Always** use `~H` or `.html.heex` files
- Use `Phoenix.Component.form/1` and `to_form/2`
- Add unique DOM IDs to key elements for testing
- **Never** use `else if` or `elsif`; use `cond` or `case`
- Use `<%!-- comment --%>` for HEEx comments

### LiveView

- Use `<.link navigate={}>` and `<.link patch={}>`, not deprecated functions
- **Avoid** LiveComponents unless specifically needed
- Name LiveViews with `Live` suffix: `AppWeb.WeatherLive`
- **Always** use streams for collections

## Zig

### Memory Safety

- Always pair allocations with deallocations (`defer allocator.free(...)`)
- Use arena allocators for request-scoped memory
- Prefer stack allocation when size is bounded
- Document ownership: who allocates, who frees

### Error Handling

- Return errors, don't panic
- Use `errdefer` for cleanup
- Prefer `[]const u8` over `[*]const u8`

## CSS

- **Never** use Tailwind CSS classes
- Use vanilla modern CSS only
- Design inspiration: GitHub Primer design system
- **No emojis** in UI or content
- All styling uses CSS variables in `assets/css/theme/tokens.css`

## Internationalization

**All user-facing strings must use gettext.** When adding or modifying UI text:

1. Wrap strings with `gettext("...")` in templates and modules
2. Run `mix gettext.extract` to extract new strings
3. Run `mix gettext.merge priv/gettext` to update all locale PO files
4. Ensure translations are provided for all supported locales
