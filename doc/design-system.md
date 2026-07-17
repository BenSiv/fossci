# Design System

fossci's own pages (`src/html.lua`) share one small set of CSS custom
properties and one reusable interaction component, rather than every page
inventing its own spacing/radius/hover treatment. This is a living
document -- it grows as new shared patterns get extracted, and it's the
place to check before a deployment's own CSS (in `software`, see below)
reinvents something fossci already provides a token or component for.

## Tokens

| Token | Default | Used for |
|---|---|---|
| `--fossci-radius-sm` | `8px` | buttons, inputs, small cards, nav items |
| `--fossci-radius-md` | `12px` | panels, modals |
| `--fossci-radius-lg` | `16px` | page-level containers |
| `--fossci-radius-pill` | `999px` | circular/pill controls (e.g. a floating toggle) |
| `--fossci-transition` | (see `src/html.lua`) | hover/active state changes on interactive elements |

Every hardcoded radius/transition literal in `src/html.lua` was retrofit to
`var(--fossci-radius-*, same-px)` / `var(--fossci-transition)` in commit
`3d50607` ("Design system foundation"). The `, same-px` fallback is
deliberate: a deployment that never defines the custom property gets
byte-identical rendering to before the retrofit, so adopting the token is
supposed to be a pure no-op until a deployment's own CSS actually
overrides the variable.

**A deployment overriding these tokens changes fossci's own generic
pages** (browse/detail/register/sql -- anywhere `src/html.lua` renders),
not just that deployment's own chrome. That's the point (one brand
palette, one set of radii, applied everywhere), but it also means a
deployment-side value change (e.g. redefining `--fossci-radius-md`) is a
real visual change to fossci's pages, not a cosmetic tweak local to the
deployment's own markup -- see the Celleste-Bio example in the note
below.

## Hover-popover component

`html.popover_css()` / `html.popover_js()` (`src/html.lua`, added in
`3d50607`) is the generic "reveal detail on hover instead of cramming it
into the default view" primitive. First applications:

- Data-index row counts (`html.render_index`) -- hover the entity-type
  name to see its row count, instead of an always-visible inline badge.
- Entity-reference links in browse/detail/sql (`render_reference_value`)
  -- hover a reference value to see a lazy-fetched preview card, backed by
  `/api/preview` (`src/cgi.lua`).

`render_browse`/`render_detail`/`render_sql` each take a trailing `nonce`
parameter (matching `html.render`'s existing `FOSSIL_NONCE` convention)
because they now embed an inline `<script>` for the popover's lazy-fetch
behavior -- any new page that wants the popover needs to thread `nonce`
through the same way.

**The popover is positioned relative to its trigger element's own
document flow.** A caller that puts a popover trigger inside a container
with `overflow: hidden`/`auto`/`scroll` on the cross axis needs to either
give the popover `position: fixed` (computed from
`getBoundingClientRect()` at hover/focus time) or make sure the
container's overflow is genuinely allowed on that axis -- otherwise the
popover either gets clipped or (if `visibility: hidden` rather than
`display: none` while inactive) silently expands the container's
scrollable content box even though nothing is visibly overflowing. This
is exactly what happened in Celleste-Bio's own deployment nav (a
`.fossci-nav-label` hover tooltip inside a `overflow-y: auto` sidebar);
see `software`'s `docs/fossci-ui-bugs.md` for the concrete writeup. The
lesson is generic, so it's recorded here for the next component that
reveals something on hover inside a scrollable container.

## Auditing a token retrofit

A retrofit commit's implicit contract is "no visual change" -- every
literal becomes `var(--token, same-value)`. That contract is easy to
violate by accident in two ways worth checking for explicitly next time,
found the hard way in the Celleste-Bio deployment's own CSS after
`3d50607`:

1. **A value drift disguised as token adoption.** `border-radius: 10px`
   becoming `border-radius: var(--fossci-radius-md, 12px)` is *not* a
   no-op -- the fallback value itself changed (10 -> 12), so anywhere the
   custom property isn't independently redefined now renders differently
   than before. Diff the literal fallback against the original literal,
   not just "did it become a `var()` call."
2. **New elements added in the same change don't inherit the audit for
   free.** A retrofit pass naturally focuses on existing hardcoded
   literals; an element added in the *same* commit (e.g. a new button
   next to the thing being retrofitted) can be missed entirely --
   ending up with no radius/transition treatment at all rather than a
   wrong one. Worth a second pass specifically over anything new in the
   diff, not just everything old.

## Known gaps (Phase 2 candidates)

- Ambient `title` attributes on a shared container (e.g. Fossil's own
  `<nav class="mainmenu" title="Main Menu">`) leak through to every child
  link that doesn't set its own `title`, producing a misleading tooltip
  on hover/focus for assistive tech and native browser tooltips alike --
  independent of whatever CSS-only hover-label component
  (`.fossci-nav-label`-style) is layered on top for sighted mouse users.
  Any future icon-only nav/toolbar should set (or explicitly clear) a
  per-item `title`/`aria-label`, not rely on a CSS-only visual tooltip.
- No project-wide lint/check yet catches "hardcoded radius/transition
  literal introduced after the retrofit" -- currently relies on manual
  review. A cheap grep-based check (flag any `border-radius:` or
  `transition:` literal in `src/html.lua` or a deployment's CSS that
  isn't a `var(--fossci-...)` call) would catch regressions like the
  ones above automatically instead of by manual UI testing.

See `software`'s `docs/fossci-ui-bugs.md` for the concrete bugs found in
the Celleste-Bio deployment's own CSS/nav (navbar horizontal scroll,
tooltip text, button/container radius inconsistency) -- those are
deployment-specific instances of the two general gaps above, not fossci
core bugs, so they're tracked in `software`, per the layering rule in
`software/docs/fossci-architecture.md`.
