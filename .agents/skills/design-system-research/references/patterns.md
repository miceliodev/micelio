## Design System Patterns (Polaris, Stripe, Primer)

Distilled guidance from Shopify Polaris, Stripe UI/Elements, and GitHub Primer for tokens, components, and layouts. Use this to make Micelio consistent and purposeful.

### Tokens
- Palette framing
  - Polaris: layered neutrals for surfaces, subtle borders, reserved accent; success/danger are calm, not neon.
  - Stripe: tight semantic scale (primary accent + muted neutrals), generous state alphas for focus/hover.
  - Primer: semantic tokens over base colors; separate text vs surface tokens; activity heatmaps show how to build intensity ramps.
- Spacing
  - All three rely on 4/8px ramps; large gaps come from stacking base units, not magic numbers.
- Typography
  - Polaris/Stripe/Primer rely on hierarchy via weight and case, not size jumps; body base ~14–16px with 400/500/600 weight ladder.
- Elevation and borders
  - Primer/Polaris favor 1px borders + light shadow for hover/focus; Stripe keeps shadows minimal and crisp.
- Motion
  - Stripe: quick ease for micro-interactions (150–200ms), distance-driven.
  - Polaris: low-motion option, opacity/translate only.
  - Primer: subtle hover/focus transitions; avoid springy bounces.
- States
  - Focus: clear outline ring separated from fill; hover uses surface tint, not full-color flood.
  - Disabled: reduce opacity and pointer events; keep text legible.

**Token checklist**
- Define semantic tokens (text, surface, border, accent, success, warning, danger) with paired alpha values for states.
- Keep a single base font size; use weights for hierarchy.
- Use 4/8/16/24 spacing; derive all gaps/margins from the ramp.
- Provide focus ring color and thickness separate from borders.
- Keep elevation to 0/1/2 tiers; pair with border colors.

### Components
- Buttons
  - Stripe: primary solid, secondary ghost/outline, danger solid; compact padding; clear loading affordance.
  - Polaris: destructive variant matches danger tokens; primary used sparingly per view.
  - Primer: ghost/link buttons for inline actions; consistent focus outlines.
- Inputs/forms
  - Polaris: sectional forms with clear group labels, inline help, and error text beside the field.
  - Stripe: inline validation, subdued placeholders, strong focus ring.
  - Primer: quiet backgrounds with 1px border; monospaced code fields.
- Navigation
  - Polaris/Stripe: top bar + secondary tabs or sidebar; current state via pill/underline, not bold alone.
  - Primer: left rail for product areas, horizontal tabs for scope.
- Cards/surfaces
  - Polaris: soft surface, border + slight shadow on hover; strong titles with helper text.
  - Stripe: contrast between canvas and card; padding 16–24px; iconography minimal.
  - Primer: surface tokens for list rows and cards; hover tint instead of big lifts.
- Tables/lists
  - Primer: zebra only when dense; padding 12–16px; sticky headers; inline status pills.
  - Stripe: single-line rows with muted meta text; right-aligned numerics.
  - Polaris: bulk actions above tables; checkboxes aligned left; compact toolbar.
- Feedback
  - Polaris: inline banners with icon + title + body; subdued background.
  - Stripe: toast/snackbar for transient confirmation; avoid blocking modals.

**Component checklist**
- Buttons: one primary per view; secondary/ghost for secondary actions; danger for irreversible actions.
- Inputs: 1px border, clear focus ring, helper/error text aligned under field; avoid placeholder-as-label.
- Nav: highlight current route with underline/pill; provide affordance for collapse on narrow widths.
- Cards: use border + slight hover tint; title + optional meta + action group aligned right.
- Tables: consistent cell padding; text-left labels, text-right numerics; sticky header for long lists.
- Banners/toasts: include icon + concise title + detail line; use semantic colors from tokens.

### Layouts
- Spacing rhythm
  - Use 8px grid with 24px section gaps for page-level blocks; 16px gaps within sections; 8px for tight pairs (label + input).
  - Vertical rhythm: stack sections with consistent gap; avoid ad-hoc margins on individual children—prefer parent gap.
  - Horizontal rhythm: gutter 16–24px between columns; maintain equal gutters at edges.
- App shell
  - Primer: left sidebar for primary IA, top bar for search/profile; content max-width ~1280–1360px.
  - Polaris: wide canvas with generous padding; sticky action bar for form-heavy pages.
  - Stripe: whitespace-rich canvas; avoid boxed layouts unless nested flows.
- Home/dashboard
  - Stripe: hero value + concise CTA; stats grid (2–4 cards) with trend pills; recent activity list.
  - Polaris: page header with title + primary action + contextual help; cards grouped by topic.
  - Primer: KPIs across top, stream/list below; consistent gutters (24px).
- List -> detail
  - Keep list searchable/filterable; detail page starts with title + meta + primary action cluster.
  - Related content (activity, history, attachments) in secondary column or tabs.
- Forms
  - Polaris: section headers with descriptions; inline validation; sticky footer actions.
  - Stripe: two-column for desktop when fields are short; single-column for long text; predictable tab order.
  - Primer: use description lists for read-only summaries; same spacing as tables for alignment.
- Tables + filters
  - Top bar: search, filters, date picker, bulk actions; avoid burying filters.
  - Empty state: icon/illustration + headline + primary CTA; muted secondary link for docs.
- Modals/drawers
  - Stripe: drawers for quick edits; modals only for critical confirmations.
  - Polaris/Primer: modals have clear title, concise body, primary and secondary buttons right-aligned.

**Layout checklist**
- Shell: maintain gutters (16–24px); keep max content width; ensure nav is responsive (collapse/overlay on mobile).
- Dashboard: top strip of KPIs; secondary zone for lists/activities; align cards to a grid.
- Forms: group fields with headings; keep actions sticky; show inline errors.
- Lists/tables: include sort/filter/search; empty states are instructive, not just decorative.
- Detail pages: title + status/meta + primary actions; secondary content in tabs or right rail.

### Applying to Micelio
- Start with Micelio tokens (nature palette, unified font size) and map semantics: text/surface/border/primary/success/warning/danger/focus.
- Use weight-driven hierarchy (bold/semibold/medium) instead of size jumps; headings can switch font-family for character.
- Favor border + hover tint for interactive surfaces; keep elevation minimal to match Primer/Polaris restraint.
- Keep spacing on the 8px grid; avoid arbitrary margins.
