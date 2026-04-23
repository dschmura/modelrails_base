# Footer Cohesion — Design Spec

**Goal:** Pull the floating "Manage cookies" link into the footer, regroup the nav links into two semantic clusters separated by a divider, and restructure the footer into a two-row layout with a centered copyright. Behave responsively at mobile / tablet / desktop widths.

**Scope:** One partial ([app/views/shared/_footer.html.erb](app/views/shared/_footer.html.erb)) restructured, the Biscuit gem's floating manage-link hidden via CSS, one I18n key added, two specs (view + system). No changes to the gem, the a11y-sim partial, or the application layout.

---

## Motivation

Three problems in the current footer:

1. **The Biscuit gem's `biscuit-manage-link` is `position: fixed` at `bottom: 0.5rem left: 1rem`** — a persistent floating button disconnected from the page flow. On mobile it eats thumb space; on desktop it's visually orphaned from the privacy-related links in the footer it logically belongs with.
2. **The nav row is a flat strip of 4 links** (About · Privacy · Contact · Docs) with no visual hierarchy. The user can't tell at a glance which links are product-related vs legal-related.
3. **The right-side cluster (a11y-sim + copyright) risks overflowing on narrow screens** — the previous fix was `flex-wrap` which works but doesn't produce an intentional-looking layout on 375px viewports.

The Biscuit gem exposes `click->biscuit#reopen` as a public Stimulus action on a button with `data-biscuit-target="manageLink"` (the very element we're hiding). Rendering our own footer link with the same `data-action` reopens the preferences dialog without any gem patching.

## Non-Goals

- Changing the a11y-sim trigger's look, position, or behavior. It stays as-is.
- Adding social links, newsletter signup, or sitemap expansion. This is a pure re-structure of existing content.
- Changing the Biscuit gem's consent banner itself (the full-width bottom bar on first visit). Only the post-consent floating "Manage cookies" link is replaced.
- Internationalizing this beyond English. Translation is a separate workstream.

---

## Architecture — the two-row footer

```text
┌─────────────────────────────────────────────────────────────────────────┐
│ Row 1  [Brand]  [About Docs] │ [Privacy Contact Manage-cookies]  …  [Dev Trigger] │
│                                                                         │
│        ─── horizontal divider ──────────────────────────────────────    │
│                                                                         │
│ Row 2                        © 2026 ModelRails. All rights reserved.    │
└─────────────────────────────────────────────────────────────────────────┘
```

- **Row 1** at desktop (`lg:` and above): brand left → two nav clusters with a 1px × 14px vertical divider between them → `flex-1` spacer → a11y-sim trigger right.
- **Divider** between rows: a 1px horizontal line using `border-border` tokens, full-width, `aria-hidden="true"`.
- **Row 2**: centered copyright, smaller text size (`text-xs`), muted color (`text-text-muted`).

## Link clustering

| Cluster         | Links                            | aria-label                             |
| --------------- | -------------------------------- | -------------------------------------- |
| Product         | About, Docs                      | `t("footer.aria.product")` = "Product" |
| Legal & privacy | Privacy, Contact, Manage cookies | `t("footer.aria.legal")` = "Legal and privacy" |

"Contact" sits in the Legal cluster (not Product) because in practice contact links answer "how do I follow up with this company about something uncertain" — which rhymes with Privacy more than Product.

## Responsive behavior

All driven by native Tailwind breakpoints — no custom media queries.

### Desktop (`lg:` ≥ 1024px)

- Row 1: `flex items-center gap-6`. Brand, nav clusters, `flex-1` spacer, a11y-sim trigger all inline.
- Clusters side-by-side with visible vertical divider.

### Tablet (`md:` 768–1023px / `sm:` 640–1023px)

- Row 1: `flex flex-wrap items-center gap-4 justify-center`. Items wrap if they exceed width. Vertical divider stays between nav clusters.
- a11y-sim trigger wraps to a new line gracefully rather than being squeezed.

### Mobile (< 640px)

- Row 1: `flex flex-col items-center gap-5`. Stacks vertically: brand, Product cluster, Legal cluster, dev trigger.
- Vertical divider is hidden (`hidden sm:block`) — visual noise without value at this width.
- Nav clusters each keep `flex items-center gap-5` horizontally but wrap if they overflow.

### Copyright row

- Always centered via `text-center`.
- `text-xs text-text-muted` at all viewport widths (no responsive changes).

---

## Hiding the gem's floating manage-link

Add one CSS rule to [app/assets/tailwind/application.css](app/assets/tailwind/application.css):

```css
/* Hide Biscuit's post-consent floating button; we render our own footer link. */
.biscuit-manage-link {
  display: none !important;
}
```

The `!important` is warranted because the gem itself sets `position: fixed` and default display inline-block via its own stylesheet, and we want to unconditionally override. Gem consent/preferences banner functionality is untouched — we're only hiding the reopen affordance.

## The footer link that replaces the floater

Biscuit's gem renders a `<button data-biscuit-target="manageLink">` inside its own `data-controller="biscuit"` element. The gem's `#reopen` Stimulus action is scoped to that element, so we can't just put `data-action="click->biscuit#reopen"` on a footer button outside the banner's scope.

Two reasonable solutions:

1. **Mount `data-controller="biscuit"` on the footer** to bring the reopen action into scope. Risks unexpected interactions with the gem's other targets (`manageLink`, `banner`, `preferencesPanel`, `categoryCheckbox`) which may be searched for during connect.
2. **Dispatch through the DOM** — render a footer button that clicks the gem's hidden manage-link element via a tiny Stimulus controller. No assumption about gem internals; works as long as the gem keeps rendering the `.biscuit-manage-link` button somewhere in the document.

**Decision: solution 2.** Add `app/javascript/controllers/footer_controller.js`:

```js
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  reopenCookies(event) {
    event.preventDefault()
    document.querySelector(".biscuit-manage-link")?.click()
  }
}
```

Footer button markup:

```erb
<button type="button"
        data-controller="footer"
        data-action="click->footer#reopenCookies"
        aria-haspopup="dialog"
        class="text-sm text-text-muted hover:text-interactive-hover
               focus:outline-none focus:ring-2 focus:ring-interactive-focus rounded">
  <%= t("footer.manage_cookies") %>
</button>
```

Two hops (footer button click → dispatch → gem button) in exchange for zero gem coupling.

---

## Files Touched

| Path | Change |
| ---- | ------ |
| [app/views/shared/_footer.html.erb](app/views/shared/_footer.html.erb) | Full rewrite of partial: two-row structure, link clustering with vertical divider, responsive stacking, Manage-cookies footer link |
| [app/assets/tailwind/application.css](app/assets/tailwind/application.css) | Append one `display: none !important` rule for `.biscuit-manage-link` |
| `app/javascript/controllers/footer_controller.js` | New Stimulus controller (~12 lines) with `reopenCookies` action |
| [config/locales/en/application.en.yml](config/locales/en/application.en.yml) | Extend the existing `footer:` key tree with `manage_cookies` and a nested `aria:` group (`product`, `legal`) |
| `spec/views/shared/footer_spec.rb` | New view spec |
| `spec/system/footer_cookies_spec.rb` | New system spec: clicking Manage cookies reopens Biscuit banner |

Three files modified, three files created. Net lines: ~120.

---

## Accessibility (WCAG 2.2 AAA)

- **Nav landmarks:** Each cluster is a `<nav aria-label="…">` so screen readers can announce and skip by group.
- **Divider:** `<span class="h-[14px] w-px bg-border" aria-hidden="true">` — a presentation-only element.
- **Target size:** All links use the existing footer anchor classes which already meet 44×44 via line-height + padding.
- **Color contrast:** All uses existing `text-text-muted` on `bg-surface`, already AAA per [2026-04-16-aaa-contrast-tokens-design.md](docs/superpowers/specs/2026-04-16-aaa-contrast-tokens-design.md).
- **Manage cookies button:** `<button>` (not `<a>`) because it dispatches a JS action, not navigating. Uses `aria-haspopup="dialog"` to announce that it opens the preferences panel.
- **Copyright row:** `<p>` element, not heading — copyright text isn't navigational structure.

## Decisions made explicit

- **Dev trigger is visible on all viewports, including mobile.** Alternative was `hidden sm:inline-flex` (hide on mobile). Decision: keep visible. Rationale: the trigger is dev-only and renders only in `Rails.env.development?`, so production mobile users never see it. A dev on mobile emulation still needs the toggle. Cost of keeping is zero.
- **"Contact" sits in the Legal cluster, not Product.** Rationale above.
- **Two-hop Stimulus dispatch to Biscuit** (footer#reopenCookies → dispatch click on hidden gem button). Alternative: mount `data-controller="biscuit"` on the footer element. Decision: dispatch-through-DOM is simpler and doesn't touch the gem's controller lifecycle.

---

## Testing

### View spec — structure

New file: `spec/views/shared/footer_spec.rb`

Asserts:

- Two `<nav>` elements with correct `aria-label` values
- Product cluster contains About and Docs links
- Legal cluster contains Privacy, Contact, and Manage cookies
- Manage cookies is a `<button>` with the correct `data-action`
- Copyright text is present and centered (class check)
- Horizontal divider has `aria-hidden="true"`

### System spec — Manage cookies flow

New file: `spec/system/footer_cookies_spec.rb`

Asserts:

- Visit a page with the footer; click Manage cookies
- Biscuit preferences panel appears (visible, not hidden)
- Clicking a category checkbox + Save closes the panel and persists consent

This is the integration test that proves the hidden Biscuit button is properly dispatched to.

## Rollout

- No migration.
- No feature flag — the change is purely structural. If it breaks, revert one commit.
- Biscuit gem unchanged; the floating manage-link still renders in the DOM but is CSS-hidden. If the gem is ever updated or removed, our CSS rule becomes dead but harmless.

## Open Questions

None.
