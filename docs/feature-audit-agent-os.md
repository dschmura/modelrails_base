# Feature Audit: modelrails_agent_os → modelrails_base

Evaluated 2026-03-28. Features grouped by category.
Check the box to mark a feature for migration. Cross out to skip.

---

## Authentication & Security

- [ ] **OAuth: Facebook & Okta** — Additional OAuth providers beyond Google/GitHub
- [ ] **Admin user management** — Super admin panel to view/edit/suspend/unlock users
- [ ] **Admin audit logging** — Track all admin actions with IP, user agent, change diffs
- [ ] **Super admin role** — Platform-level admin distinct from workspace owner
- [ ] **Account suspension by admin** — Admin can permanently suspend accounts (vs. auto-lock)
- [ ] **App configuration panel** — Runtime feature flags (self-registration, invite-only, etc.)
- [ ] **Structured error classes** — Domain-specific exception hierarchy (AuthError, InvitationError, etc.)
- [ ] **Password complexity rules** — Requires uppercase, lowercase, numbers, special characters
- [ ] **Filter parameter logging** — Extended list (OTP, SSN, CVV, certificates) beyond Rails defaults

## Workspaces & Multi-Tenancy

- [ ] **Tenanted query enforcement** — Middleware raises if tenant-scoped model queried without workspace context
- [ ] **Workspace configuration cascade** — Global → workspace → user settings override chain
- [ ] **Feature toggles per workspace** — Enable/disable invitations, teams, custom roles, guest access per workspace
- [ ] **Member/team limits** — Configurable max members and max teams per workspace *(partial: data model exists)*
- [ ] **Workspace archival with grace period** — Soft delete with configurable grace period before permanent deletion *(partial: soft delete exists)*
- [ ] **Custom domain support** — Enterprise workspaces get custom domains with DNS verification
- [ ] **Subdomain routing** — Workspace resolution via subdomain with reserved subdomain list
- [ ] **Strict privacy mode** — Only admins see hidden teams when enabled

## Teams & Collaboration

- [ ] **Teams (within workspaces)** — Team layer between workspace and resources (leader/member/viewer roles) *(base uses Projects instead)*
- [ ] **Team visibility control** — Teams can be visible to all workspace members or hidden
- [ ] **Team leadership transfer** — Leaders can transfer leadership to other members
- [ ] **Team pinning in sidebar** — Pin frequently-used teams for quick sidebar access
- [ ] **Resource sharing between teams** — Share resources across teams with read/edit/full permissions
- [ ] **Expiring resource shares** — Shared access can have optional expiration dates
- [ ] **Team dashboard** — Tabbed view with members + resources per team

## Resources & Content

- [ ] **Photos resource type** — Photo uploads with viewer
- [ ] **Videos resource type** — Video uploads with player
- [ ] **Links resource type** — Bookmarkable links with auto-favicon fetching
- [ ] **Notes resource type** — Simple text notes
- [ ] **Resource tabs by type** — Filter resources by type (docs, links, notes, photos, videos)
- [ ] **Resource pagination** — Configurable per-page (10/20/50/100) with Pagy

## Activity & Real-Time

- [ ] **Activity filtering & search** — Filter by user, type, date range presets, custom date ranges
- [ ] **20+ tracked event types** — Workspace renamed, plan changed, role changed, visibility changed, etc. *(partial)*

## UI & Design System


- [x] **Class-based dark mode toggle** — Three-way toggle (light/dark/system) with Stimulus controller *(partial: system-only via media query)*
- [x] **Semantic design tokens** — CSS custom properties for surfaces, text, borders, status, brand colors
- [ ] **Toast notification system** — Auto-dismiss notices, persistent errors, progress bar, stack management
- [ ] **Modal system** — Focus trap, escape-to-close, backdrop click, Turbo Frame integration
- [ ] **Icon component (72+ icons)** — SVG icon registry with outline/solid variants, size presets, ARIA support
- [ ] **TailwindFormBuilder** — Custom form builder with consistent styling, validation states
- [ ] **Drag-and-drop file upload** — Dropzone controllers for file and URL-based uploads
- [ ] **Color picker** — Hue slider with OKLCH gradient and preset color palette
- [ ] **Pagination component** — Simple and full variants with Pagy, Turbo-aware
- [ ] **Info popovers** — Hover/click information tooltips
- [ ] **Filter bar component** — Reusable search/filter UI for lists
- [ ] **Stat card component** — Dashboard metric cards
- [ ] **Tab navigation component** — Reusable tabbed interface with Turbo support
- [ ] **User hover card** — Quick user info on hover
- [ ] **Avatar group component** — Stacked avatar display for member lists
- [ ] **Banner system** — Hero, lifecycle, invitation, and role banners *(partial: hero only)*
- [ ] **Container page layout** — Max-width container with responsive padding
- [ ] **Reduced motion support** — All animations respect `prefers-reduced-motion`
- [ ] **OKLCH brand palette generation** — Generate 9-shade color palette from a single hue value

## Developer Ergonomics

- [x] **letter_opener_web** — Preview sent emails in browser at /letter_opener
- [ ] **rack-mini-profiler** — Request/view performance profiling in dev
- [ ] **Guard + guard-rspec** — Auto-run tests on file save
- [x] **hotwire-spark** — Live reload for views and CSS without restart
- [x] **Lefthook git hooks** — Pre-commit (RuboCop fix) + pre-push (Brakeman + RSpec + lint)
- [ ] **bin/doctor** — Health check script (Ruby version, DB, credentials, tools)
- [ ] **Parallel tests** — Split RSpec across 4 workers for faster CI
- [ ] **test-prof** — Factory profiling and event profiling for test optimization
- [X] **axe-core-rspec** — Automated accessibility testing in specs
- [ ] **database_cleaner** — Test isolation beyond transactional fixtures
- [ ] **Seed scenarios** — sales/dev/training/full seed profiles for different use cases
- [ ] **RuboCop (omakase)** — Opinionated Rails linting with auto-fix
- [ ] **bundler-audit** — Audit gem dependencies for known CVEs
- [x] **CI pipeline (GitHub Actions)** — Security scan + lint + parallel tests + system test screenshots
- [x] **Markdown + ERB linting** — markdownlint-cli + herb linter
- [ ] **Vitest** — JavaScript unit testing
- [ ] **Kamal deployment** — Docker-based deployment with Traefik proxy *(partial: config exists)*
- [ ] **Custom rake tasks** — admin:grant, icons:import, view_layer:metrics, etc. *(partial)*
- [ ] **Structured error hierarchy** — ApplicationError base with domain-specific subclasses
- [ ] **Rack::Attack** — Rate limiting middleware with bot blocking and distributed throttle
- [ ] **AppConfiguration singleton** — Database-backed runtime feature flags editable by admins

## Not in agent_os (greenfield if desired)

- [ ] WebAuthn / Passkeys
- [ ] Two-factor authentication (TOTP/MFA)
- [ ] User impersonation
- [ ] IP whitelisting
- [ ] Password expiration policies
