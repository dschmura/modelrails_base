# User Menu Dropdown Design Spec

**Date:** 2026-04-02
**Status:** Final
**Depends on:** Phase 3 complete (auth, workspaces, projects, all passing)

---

## 1. Goal

Add a user menu dropdown triggered by an avatar circle in the header. Authenticated users see their name, email, a profile link, and sign out. Unauthenticated users see a "Sign In" link instead. Replace the existing workspace switcher Stimulus controller with a single reusable dropdown controller that handles all dropdown menus.

---

## 2. Decisions Made

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Trigger element | Avatar circle (photo or initials fallback) | Familiar pattern (GitHub, Slack), clear visual identity anchor |
| Menu contents | Name/email header + Profile link + Sign Out | GitHub-style — shows identity context without extra clicks |
| Unauthenticated state | "Sign In" link (no dropdown) | No menu needed when there's nothing to show |
| Dropdown controller | Single reusable `dropdown_controller.js` | DRY — handles user menu, workspace switcher, future dropdowns |
| Keyboard navigation | Full WAI-ARIA menu pattern | WCAG AAA requires arrow keys, Home/End, Escape for menu widgets |
| Existing workspace switcher | Migrate to reusable controller, delete old | Eliminates duplicated JS logic |
| Mobile | User menu items in hamburger panel | Avatar dropdown hidden below `md` breakpoint, items in mobile menu |
| Implementation approach | TDD: red-green-refactor | Write failing specs first, implement to pass |

### Deferred

- Theme toggle inside user menu (keep in header for now)
- Admin panel link (no admin panel in base)
- Hover-to-open support (click is sufficient, hover is a forker tweak)

---

## 3. Components

### 3.1 Dropdown Controller (`app/javascript/controllers/dropdown_controller.js`)

Replaces `workspace_switcher_controller.js`. Generic, reusable for any dropdown.

**Stimulus targets:**
- `menu` — the dropdown panel
- `button` — the trigger element

**Behavior:**
- **Toggle:** Click on `button` toggles `menu` visibility
- **Close triggers:** Escape key, click outside, Tab out of last menu item
- **Arrow navigation:** Up/Down moves focus between `[role="menuitem"]` elements
- **Home/End:** Jump to first/last menu item
- **Focus management:** First `[role="menuitem"]` focused on open; focus returns to `button` on close
- **ARIA:** Updates `aria-expanded` on `button`; menu has `role="menu"` and `aria-orientation="vertical"`

**No hover support, no fixed positioning, no copy-to-clipboard** — those are agent_os features not needed here.

### 3.2 User Menu Partial (`app/views/shared/_user_menu.html.erb`)

Rendered in the header. Two states:

**Authenticated:**
```
[Avatar ▾]  ← click trigger (36px circle, photo or initials)
┌─────────────────────┐
│ Jane Doe             │  ← bold, text-text-heading
│ jane@example.com     │  ← text-sm, text-text-muted
├─────────────────────┤
│ Profile              │  ← link to edit_account_profile_path
├─────────────────────┤
│ Sign out             │  ← button_to delete session_path
└─────────────────────┘
```

**Unauthenticated:**
```
[Sign In]  ← plain link to new_session_path, no dropdown
```

### 3.3 Header Updates (`app/views/shared/_header.html.erb`)

- Remove inline "Profile" and "Sign Out" text links from desktop nav
- Add `<%= render "shared/user_menu" %>` in the right side of the header
- Keep theme toggle in header (not in dropdown)
- Keep workspace switcher, but change `data-controller="workspace-switcher"` to `data-controller="dropdown"`

### 3.4 Workspace Switcher Migration

`_workspace_switcher.html.erb`:
- Change `data-controller="workspace-switcher"` to `data-controller="dropdown"`
- Change `data-workspace-switcher-target="menu"` to `data-dropdown-target="menu"`
- Add `data-dropdown-target="button"` to the trigger element
- Verify `role="menu"` and `role="menuitem"` are present
- Delete `app/javascript/controllers/workspace_switcher_controller.js`

### 3.5 Mobile Menu Updates

In the mobile menu panel (hamburger):
- Add user identity section: avatar + name + email (display only, not a link)
- Add "Profile" link
- Replace or keep "Sign Out" link (already present in mobile menu)
- When unauthenticated: show "Sign In" and "Sign Up" links (already present)

---

## 4. Styling

All styles use existing semantic design tokens. No new CSS.

**Avatar circle:**
- 36px (`w-9 h-9`), `rounded-full`, `object-cover` for photos
- Initials fallback: `bg-interactive`, `text-text-on-interactive`, `text-sm font-semibold`
- Focus ring: `focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-interactive-focus`

**Dropdown panel:**
- `bg-surface-raised`, `border border-border`, `rounded-lg`, `shadow-lg`
- Width: `w-64` (256px)
- Position: `absolute right-0 mt-2`, `z-50`
- Dividers: `border-t border-border` between sections

**Menu items:**
- `min-h-[44px]` touch target (WCAG AAA)
- `px-4 py-2` padding
- `text-text-body hover:bg-surface hover:text-interactive`
- `focus:outline-none focus:bg-surface focus:text-interactive` for keyboard navigation
- `role="menuitem"`, `tabindex="-1"` (focus managed by JS, not Tab order)

---

## 5. Accessibility

- **ARIA pattern:** WAI-ARIA Menu Button pattern
- **Trigger:** `aria-haspopup="true"`, `aria-expanded="false|true"`, `aria-controls="user-menu"`
- **Menu:** `role="menu"`, `aria-orientation="vertical"`, `aria-labelledby="user-menu-button"`
- **Items:** `role="menuitem"`, `tabindex="-1"`
- **Keyboard:** Escape, ArrowUp, ArrowDown, Home, End
- **Focus:** Auto-focus first item on open, return focus to trigger on close
- **Touch:** 44px minimum targets on all interactive elements
- **Screen reader:** Avatar trigger has `aria-label` with user's name (e.g., "User menu for Jane Doe")
- **Contrast:** All text meets WCAG AAA 7:1 ratio via semantic tokens

---

## 6. Testing Strategy (TDD)

All tests written before implementation. Red-green-refactor cycle.

### 6.1 Request Specs

**User menu visibility:**
- Authenticated user sees avatar trigger in header (presence of user menu markup)
- Unauthenticated user sees "Sign In" link, no avatar trigger

**User menu links:**
- Profile link points to `edit_account_profile_path`
- Sign out form posts DELETE to `session_path`

### 6.2 System Specs (Playwright)

**Dropdown interaction:**
- Click avatar opens dropdown, click again closes
- Click outside dropdown closes it
- Escape key closes dropdown
- Profile link navigates to profile page
- Sign out link ends session and redirects to sign-in

**Keyboard navigation:**
- Arrow Down from trigger opens menu and focuses first item
- Arrow Down/Up moves between menu items
- Home/End jump to first/last item
- Tab out of menu closes it

### 6.3 Workspace Switcher Regression

- Workspace switcher still opens/closes on click
- Workspace switcher keyboard navigation works (Escape closes)
- Workspace links navigate correctly

### 6.4 Controller JS Tests (optional, Stimulus)

If the project has a JS test setup, test the dropdown controller in isolation. Otherwise, system specs cover the behavior.

---

## 7. Files

| File | Action |
|------|--------|
| `app/javascript/controllers/dropdown_controller.js` | Create |
| `app/javascript/controllers/workspace_switcher_controller.js` | Delete |
| `app/views/shared/_user_menu.html.erb` | Create |
| `app/views/shared/_header.html.erb` | Modify (add user menu, remove inline links) |
| `app/views/shared/_workspace_switcher.html.erb` | Modify (swap controller references) |
| `config/locales/en/navigation.en.yml` | Modify (add user menu keys if needed) |
| `spec/requests/` | Modify (add user menu presence checks) |
| `spec/system/user_menu_spec.rb` | Create |
