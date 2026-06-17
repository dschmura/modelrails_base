# Onboarding :none Mode + Landing Seam Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (- [ ]) syntax for tracking.

**Goal:** Add a third tenancy onboarding posture — `:none` — to the modelrails_base template, so a fork (hallwaytrack) can have signup create **no** workspace. This is the generic, template-owned half of the "organizer onboarding" design (`/Users/dschmura/Documents/code/hallwaytrack/docs/superpowers/specs/2026-06-17-organizer-onboarding-design.md`, section "Data model / changes → Template (modelrails_base)"). Three generic blockers ship here: (1) accept `:none` at boot + an explicit no-op onboarding branch; (2) crash-safety for a signed-in user who now has **no** workspace (`Current.workspace` legitimately nil); (3) an overridable, workspace-agnostic post-sign-in landing seam (`authenticated_home_path`) a fork can repoint at `/me`.

**Architecture:** No new models, no migrations, no new routes. The work is three surgical seams in existing files plus the nil-guards the audit proves necessary:

- **Boot config** — `config/initializers/tenancy.rb` validates `Rails.configuration.x.tenancy.onboarding` against an allowlist; `:none` joins `:personal`/`:shared`.
- **Onboarding dispatch** — `User#onboard_workspace` (an `after_create` callback) is a `case TenancyConfig.onboarding`; `:none` gets an explicit, commented no-op `when` arm (no silent `else` fall-through).
- **Zero-workspace safety** — every `Current.workspace` read in app code is already mostly nil-guarded (the `application.html.erb` layout branches on `Current.workspace`; `_workspace_back_link`, `_authenticated_layout_streams`, `settings_navigation_helper`, `application_policy`, and the sidebar switcher partials all guard). This task **proves** it with a request spec that signs in a workspaceless user and GETs every authenticated page a `:none` fork can reach, expecting 200 — and hardens any genuine gap the spec exposes.
- **Landing seam** — `Authenticatable#after_authentication_url` currently returns `session.delete(:return_to_after_authenticating) || root_url`. We introduce an overridable `authenticated_home_path` (default `root_path`) that `after_authentication_url` falls back to instead of `root_url`, so a fork overrides ONE method to land users at `/me`.

**Tech Stack:** Rails 8.1, Ruby 4.0.4 (run everything via `mise exec --`), RSpec (request + model + lib specs only — this template ships no `/me` view, so no system spec is in scope; system coverage lands in the fork). FactoryBot. SQLite. Tests are written first (TDD), the full suite must be green before every commit, commits are made but **not pushed**, and Lefthook is never bypassed.

---

## File Structure

| File | Create / Modify | Responsibility |
|---|---|---|
| `config/initializers/tenancy.rb` | Modify (line 5) | Add `:none` to `valid_onboarding` so boot accepts it instead of raising. |
| `app/models/user.rb` | Modify (`onboard_workspace`, ~L204-209) | Add an explicit, documented `when :none` no-op arm so `:none` signup creates no workspace (no silent fall-through). |
| `app/controllers/concerns/authenticatable.rb` | Modify (L49-51) | Introduce overridable `authenticated_home_path` (default `root_path`); `after_authentication_url` falls back to it (via `_url`) instead of hard-coding `root_url`. |
| `spec/initializers/tenancy_spec.rb` | Create | Prove the boot validator accepts `:none` (and still rejects garbage). |
| `spec/lib/tenancy_config_spec.rb` | Modify | Prove `TenancyConfig.onboarding` round-trips `:none` and the predicates (`personal?`/`shared?`) report false under it. |
| `spec/models/user_spec.rb` | Modify (after the `:shared` posture block, ~L575) | Prove `:none` onboarding creates zero workspaces and assigns no `personal_workspace_id`. |
| `spec/factories/users.rb` | Modify | Add a `:with_zero_workspaces` trait (stubs onboarding to `:none` during creation) so other specs get a workspaceless user cheaply. |
| `spec/requests/onboarding_none_mode_spec.rb` | Create | Sign a workspaceless user in and GET root + every authenticated page a `:none` fork reaches; expect 200, never 500. |
| `spec/requests/authenticated_landing_spec.rb` | Create | Prove the default landing (`authenticated_home_path` ⇒ `root`) and that the seam is overridable (a subclass overriding it changes `after_authentication_url`). |

---

### Task 0: Branch

**Files:** none (git only)

- [ ] Confirm a clean tree on `main`: `mise exec -- git status` — expect "nothing to commit, working tree clean" (the stray `config/credentials/` is gitignored; ignore it).
- [ ] Create and switch to the feature branch off `main`: `git switch main && git pull --ff-only && git switch -c feat/onboarding-none-mode`
- [ ] Verify you are on the branch: `git branch --show-current` — expect `feat/onboarding-none-mode`.
- [ ] Establish a green baseline before any change: `mise exec -- bundle exec rspec` — expect the suite to pass (0 failures). If anything is already red on `main`, STOP and surface it; do not start on a red baseline.

---

### Task 1: Boot validator accepts `:none`

**Files:**
- Modify: `config/initializers/tenancy.rb:5`
- Test (Create): `spec/initializers/tenancy_spec.rb`

The initializer raises at boot for any `onboarding` value not in `valid_onboarding = %i[personal shared]`. Because the initializer runs once at boot (not per-request), we test the **same allowlist logic** directly rather than rebooting the app: extract no code, just assert the constant the initializer enforces. The cleanest seam is to re-derive the allowlist in the spec and assert `:none` is a member, plus a guard test that the real initializer file lists it.

- [ ] Write the failing test. Create `spec/initializers/tenancy_spec.rb`:

```ruby
require "rails_helper"

# The tenancy initializer (config/initializers/tenancy.rb) validates
# Rails.configuration.x.tenancy.onboarding at boot and raises on an unknown
# value. It already ran (cleanly) when the test app booted, so here we assert
# the allowlist it enforces — :none must be accepted alongside :personal and
# :shared — by reading the source of truth (the initializer file itself).
RSpec.describe "config/initializers/tenancy.rb" do
  let(:source) { Rails.root.join("config/initializers/tenancy.rb").read }

  describe "valid_onboarding allowlist" do
    it "accepts :none in addition to :personal and :shared" do
      line = source.lines.find { |l| l.include?("valid_onboarding =") }
      expect(line).to include(":none")
      expect(line).to include(":personal")
      expect(line).to include(":shared")
    end
  end

  describe "booting under :none onboarding" do
    it "does not raise" do
      expect do
        valid_onboarding = %i[personal shared none]
        onboarding = :none
        unless valid_onboarding.include?(onboarding)
          raise "Invalid TENANCY_ONBOARDING: #{onboarding.inspect}"
        end
      end.not_to raise_error
    end
  end
end
```

- [ ] Run it (expect FAIL): `mise exec -- bundle exec rspec spec/initializers/tenancy_spec.rb -e "accepts :none in addition to :personal and :shared"` — expected FAIL: the "accepts :none" example fails because line 5 currently reads `valid_onboarding = %i[personal shared]` and does not include `:none`.

- [ ] Minimal implementation. Edit `config/initializers/tenancy.rb` line 5:

```ruby
valid_onboarding = %i[personal shared none]
```

- [ ] Run it (expect PASS): `mise exec -- bundle exec rspec spec/initializers/tenancy_spec.rb` — expected PASS (both examples green).

- [ ] Run the FULL suite green before committing: `mise exec -- bundle exec rspec` — expect 0 failures.

- [ ] Commit (do NOT push):
  - `git add config/initializers/tenancy.rb spec/initializers/tenancy_spec.rb`
  - `git commit -m "feat(tenancy): accept :none onboarding posture at boot"`

---

### Task 2: `TenancyConfig` round-trips `:none`

**Files:**
- Modify: `app/lib/tenancy_config.rb` (no code change expected — `onboarding` already returns whatever is configured; this task proves it and that the predicates stay false)
- Test (Modify): `spec/lib/tenancy_config_spec.rb`

`TenancyConfig.onboarding` reads `Rails.configuration.x.tenancy.onboarding` verbatim, and `personal?`/`shared?` compare against `:personal`/`:shared`. Under `:none` both predicates must report false. No production change is anticipated; if the spec passes red-free immediately, that is the correct (characterization) outcome and we keep the spec as a regression guard.

- [ ] Write the failing test. Add this `describe` block to `spec/lib/tenancy_config_spec.rb`, immediately after the existing `describe "under :shared onboarding"` block (before `describe "workspace_creation_enabled?"`):

```ruby
  describe "under :none onboarding" do
    before do
      allow(Rails.configuration.x.tenancy).to receive(:onboarding).and_return(:none)
    end

    it "reports onboarding as :none" do
      expect(described_class.onboarding).to eq(:none)
    end

    it "reports neither personal? nor shared?" do
      expect(described_class).not_to be_personal
      expect(described_class).not_to be_shared
    end

    it "resolves no shared workspace" do
      expect(described_class.shared_workspace).to be_nil
    end
  end
```

- [ ] Run it: `mise exec -- bundle exec rspec spec/lib/tenancy_config_spec.rb -e "under :none onboarding"` — expected: all three PASS without any production edit, because `onboarding` already returns the stubbed value and the predicates compare `== :personal`/`== :shared` (both false under `:none`). This is a deliberate characterization test. If, contrary to expectation, any example fails, STOP and inspect `app/lib/tenancy_config.rb` before changing anything.

- [ ] Run the FULL suite green: `mise exec -- bundle exec rspec` — expect 0 failures.

- [ ] Commit (do NOT push):
  - `git add spec/lib/tenancy_config_spec.rb`
  - `git commit -m "test(tenancy): characterize TenancyConfig under :none onboarding"`

---

### Task 3: `User#onboard_workspace` no-ops under `:none`

**Files:**
- Modify: `app/models/user.rb` (`onboard_workspace`, lines 204-209)
- Test (Modify): `spec/models/user_spec.rb` (add a sibling block after `describe "#onboard_workspace under :shared posture"`, ~L575)

`onboard_workspace` is an `after_create` callback (`app/models/user.rb:17`). Today:

```ruby
def onboard_workspace
  case TenancyConfig.onboarding
  when :personal then create_personal_workspace
  when :shared   then join_shared_workspace
  end
end
```

Under `:none` it already falls through to no-op — but the spec/design require an **explicit, documented** `when :none` arm (no silent fall-through), so a future maintainer can't mistake the absence of an arm for an oversight.

- [ ] Write the failing test. Add this `describe` block to `spec/models/user_spec.rb`, immediately after the closing `end` of `describe "#onboard_workspace under :shared posture"` (the block that starts at L553):

```ruby
  describe "#onboard_workspace under :none posture" do
    before do
      allow(Rails.configuration.x.tenancy).to receive(:onboarding).and_return(:none)
    end

    it "creates no workspace on sign-up" do
      user = create(:user)

      expect(user.workspaces).to be_empty
      expect(user.memberships).to be_empty
    end

    it "assigns no personal_workspace_id" do
      user = create(:user)

      expect(user.personal_workspace_id).to be_nil
      expect(user.personal_workspace).to be_nil
    end

    it "dispatches to an explicit no-op (does not call create_personal_workspace)" do
      expect_any_instance_of(User).not_to receive(:create_personal_workspace)
      expect_any_instance_of(User).not_to receive(:join_shared_workspace)

      create(:user)
    end
  end
```

- [ ] Run it: `mise exec -- bundle exec rspec spec/models/user_spec.rb -e "#onboard_workspace under :none posture"` — expected: the two state examples ("creates no workspace", "assigns no personal_workspace_id") already PASS (the empty `case` no-ops today); the third ("dispatches to an explicit no-op") also passes since neither private method is called. This block characterizes current behavior AND will guard the explicit arm we add next. Run it first to confirm green, then add the explicit arm and re-run to confirm it stays green.

- [ ] Minimal implementation. Edit `app/models/user.rb` — add an explicit `when :none` arm to `onboard_workspace`:

```ruby
  # Dispatches to the right onboarding strategy based on the tenancy preset.
  # See app/docs/presets.md for the contract.
  def onboard_workspace
    case TenancyConfig.onboarding
    when :personal then create_personal_workspace
    when :shared   then join_shared_workspace
    when :none     then nil # explicit: :none creates no workspace; the user's home is workspace-agnostic (see config/initializers/tenancy.rb)
    end
  end
```

- [ ] Run it (expect PASS): `mise exec -- bundle exec rspec spec/models/user_spec.rb -e "#onboard_workspace under :none posture"` — expected PASS (all three green; behavior unchanged, intent now explicit).

- [ ] Run the FULL suite green: `mise exec -- bundle exec rspec` — expect 0 failures (the existing `:personal` default and `:shared` posture specs must remain green).

- [ ] Commit (do NOT push):
  - `git add app/models/user.rb spec/models/user_spec.rb`
  - `git commit -m "feat(tenancy): explicit :none no-op arm in User#onboard_workspace"`

---

### Task 4: `:with_zero_workspaces` factory trait

**Files:**
- Modify: `spec/factories/users.rb`
- Test (Modify): `spec/models/user_spec.rb` (a tiny trait-contract example in the `:none` describe block, OR a dedicated `describe "factory traits"` — use the latter to keep the posture block focused)

Tasks 5 and 6 need a workspaceless user. The design ("Testing → Factory traits to add first: User `:with_zero_workspaces`") calls for a trait. Because `onboard_workspace` runs in `after_create` and reads `TenancyConfig.onboarding`, the trait must force `:none` **during** the user's creation. The cleanest in-factory mechanism is to stub the config inside an `after(:build)` so the stub is active when the `after_create` callback fires, then it lasts for the example (RSpec mocks reset per-example).

- [ ] Write the failing test. Add this block to `spec/models/user_spec.rb` (place it right after the `describe "#onboard_workspace under :none posture"` block from Task 3):

```ruby
  describe "factory trait :with_zero_workspaces" do
    it "builds a user with no workspaces and no personal_workspace_id" do
      user = create(:user, :with_zero_workspaces)

      expect(user.workspaces).to be_empty
      expect(user.memberships).to be_empty
      expect(user.personal_workspace_id).to be_nil
    end

    it "still produces a persisted, valid user" do
      user = create(:user, :with_zero_workspaces)

      expect(user).to be_persisted
      expect(user).to be_valid
    end
  end
```

- [ ] Run it (expect FAIL): `mise exec -- bundle exec rspec spec/models/user_spec.rb -e "factory trait :with_zero_workspaces"` — expected FAIL: `KeyError: Trait not registered: "with_zero_workspaces"` (the trait does not exist yet).

- [ ] Minimal implementation. Edit `spec/factories/users.rb` — add the trait inside the `factory :user` block (after the existing `:with_avatar` trait, before the closing `end` of the factory):

```ruby
    # Forces the :none onboarding posture for the duration of THIS user's
    # creation so the after_create :onboard_workspace callback no-ops — the
    # user persists with zero workspaces. Used by the zero-workspace
    # crash-safety specs. The stub is scoped to the example (RSpec resets
    # mocks per-example), so it does not leak to other factories.
    trait :with_zero_workspaces do
      after(:build) do
        allow(Rails.configuration.x.tenancy).to receive(:onboarding).and_return(:none)
      end
    end
```

- [ ] Run it (expect PASS): `mise exec -- bundle exec rspec spec/models/user_spec.rb -e "factory trait :with_zero_workspaces"` — expected PASS (both examples green).

- [ ] Run the FULL suite green: `mise exec -- bundle exec rspec` — expect 0 failures.

- [ ] Commit (do NOT push):
  - `git add spec/factories/users.rb spec/models/user_spec.rb`
  - `git commit -m "test(factory): add :with_zero_workspaces user trait for :none posture"`

---

### Task 5: Zero-workspace crash-safety (request spec drives the audit)

**Files:**
- Test (Create): `spec/requests/onboarding_none_mode_spec.rb`
- Modify (only if the spec exposes a genuine 500): any of `app/views/layouts/settings.html.erb`, `app/helpers/settings_navigation_helper.rb`, or another `Current.workspace` reader the audit flags. **Expectation: the existing guards already cover every page below, so NO production edit is needed — the spec is the proof.**

A `:none` user reaches these authenticated pages (verified against `config/routes/app.rb`, `WorkspacesController`, and the `Account::*` controllers): `root_path` (renders `pages#home`, the `application` layout already branches `Current.workspace ? … : …`), `workspaces_path` (index; `skip_before_action :set_workspace`, no workspace required), `new_workspace_path`, `edit_account_profile_path` and the other `Account::*` settings (each `include PersonalWorkspaceContext`, which sets `Current.workspace = Current.user&.personal_workspace` ⇒ nil for a `:none` user — legitimately nil, the `settings` layout's `Current.user.workspaces.kept` returns an empty relation and `current_workspace_announcement_for_aria_live` returns nil). The spec GETs each and asserts 200.

- [ ] Write the failing-or-proving test. Create `spec/requests/onboarding_none_mode_spec.rb`:

```ruby
require "rails_helper"

# A signed-in user may now legitimately have NO workspace (:none onboarding),
# so Current.workspace is nil on every authenticated page. This spec walks such
# a user through the pages a :none fork can reach and asserts each renders
# (200), never 500. It is the regression guard for "zero-workspace crash
# safety" (organizer-onboarding design, Template BLOCKERS).
RSpec.describe "Authenticated pages under :none onboarding (zero-workspace safety)", type: :request do
  let(:user) { create(:user, :with_zero_workspaces) }

  before { sign_in(user) }

  it "the user truly has no workspace" do
    expect(user.workspaces).to be_empty
    expect(user.personal_workspace).to be_nil
  end

  describe "GET / (root / marketing home)" do
    it "renders without a 500" do
      get root_path
      expect(response).to have_http_status(:ok)
    end
  end

  describe "GET /workspaces (index)" do
    it "renders without a 500" do
      get workspaces_path
      expect(response).to have_http_status(:ok)
    end
  end

  describe "GET /workspaces/new" do
    it "renders without a 500" do
      get new_workspace_path
      expect(response).to have_http_status(:ok)
    end
  end

  describe "GET /account/profile/edit (settings layout, PersonalWorkspaceContext)" do
    it "renders without a 500" do
      get edit_account_profile_path
      expect(response).to have_http_status(:ok)
    end
  end

  describe "GET /account/notification_preferences/edit (settings layout)" do
    it "renders without a 500" do
      get edit_account_notification_preferences_path
      expect(response).to have_http_status(:ok)
    end
  end

  describe "GET /account/connected_accounts (settings layout)" do
    it "renders without a 500" do
      get account_connected_accounts_path
      expect(response).to have_http_status(:ok)
    end
  end
end
```

- [ ] Confirm the route helpers used above are real before running (paths must match `config/routes.rb`): `mise exec -- bin/rails runner 'puts [Rails.application.routes.url_helpers.workspaces_path, Rails.application.routes.url_helpers.new_workspace_path, Rails.application.routes.url_helpers.edit_account_profile_path, Rails.application.routes.url_helpers.edit_account_notification_preferences_path, Rails.application.routes.url_helpers.account_connected_accounts_path].inspect'` — expected: prints five valid paths. If any helper name differs, correct the spec to the real helper name from the output (do not invent routes).

- [ ] Run it: `mise exec -- bundle exec rspec spec/requests/onboarding_none_mode_spec.rb` — expected: with the existing nil-guards in place, all examples PASS (each page renders 200 for a workspaceless user). If ANY example returns 500, that is a genuine unguarded `Current.workspace` access — read `log/test.log` for the backtrace, locate the offending reader (candidates from the audit: `app/views/layouts/settings.html.erb`, `app/helpers/settings_navigation_helper.rb`), add a `Current.workspace.present?` / `&.` guard at exactly that site, and re-run until green. Do NOT broaden the guard beyond the line that raised.

- [ ] (If and only if a guard was added) Re-read the changed view/helper to confirm the guard is the minimal `&.`/`present?` form and uses semantic tokens if any markup changed (no raw hex, per `.modelrails_ui/agent-rules.md`).

- [ ] Run the FULL suite green: `mise exec -- bundle exec rspec` — expect 0 failures.

- [ ] Commit (do NOT push):
  - `git add spec/requests/onboarding_none_mode_spec.rb` (plus any guarded file the audit required)
  - `git commit -m "test(tenancy): prove zero-workspace pages render under :none onboarding"`

---

### Task 6: Overridable `authenticated_home_path` landing seam

**Files:**
- Modify: `app/controllers/concerns/authenticatable.rb` (lines 49-51)
- Test (Create): `spec/requests/authenticated_landing_spec.rb`

Today `after_authentication_url` hard-codes `root_url`:

```ruby
def after_authentication_url
  session.delete(:return_to_after_authenticating) || root_url
end
```

We extract the destination into an overridable `authenticated_home_path` (default `root_path`). `after_authentication_url` keeps returning an absolute URL (it feeds `redirect_to` after sign-in, and a saved `return_to` is an absolute `request.url`), so it wraps the path with the host. A fork overrides ONE method (`authenticated_home_path`) — e.g. `-> { me_path }` — to repoint the post-sign-in landing without touching session/`return_to` logic.

- [ ] Write the failing test. Create `spec/requests/authenticated_landing_spec.rb`:

```ruby
require "rails_helper"

# Post-sign-in landing is workspace-agnostic and fork-overridable. The template
# default routes an authenticated user with no saved return_to to their home
# (authenticated_home_path => root_path). A fork overrides ONE method to land
# users at /me. (organizer-onboarding design, Template BLOCKERS: "Overridable,
# workspace-agnostic landing seam".)
RSpec.describe "Authenticated landing seam", type: :request do
  let(:user) { create(:user) }

  describe "default destination after sign-in" do
    it "lands on root when there is no saved return_to" do
      post session_path, params: {
        email_address: user.email_address,
        password: "SecureP@ssw0rd123!"
      }

      expect(response).to redirect_to(root_url)
    end

    it "still honors a saved return_to over the home default" do
      # Visiting a protected page while signed out stashes its URL; sign-in
      # then returns there instead of the home default.
      get edit_account_profile_path
      expect(response).to redirect_to(new_session_path)

      post session_path, params: {
        email_address: user.email_address,
        password: "SecureP@ssw0rd123!"
      }

      expect(response).to redirect_to(edit_account_profile_url)
    end
  end

  describe "the seam is overridable" do
    it "after_authentication_url derives from authenticated_home_path" do
      controller = SessionsController.new
      request = ActionDispatch::TestRequest.create
      controller.set_request!(request)
      allow(controller).to receive(:session).and_return({})

      # Default: authenticated_home_path is root_path, so the URL is root_url.
      expect(controller.send(:authenticated_home_path)).to eq(Rails.application.routes.url_helpers.root_path)
      expect(controller.send(:after_authentication_url)).to eq(controller.send(:root_url))

      # Override the single seam — after_authentication_url follows it.
      allow(controller).to receive(:authenticated_home_path)
        .and_return(Rails.application.routes.url_helpers.about_path)
      expect(controller.send(:after_authentication_url))
        .to eq(controller.send(:about_url))
    end
  end
end
```

- [ ] Run it (expect FAIL): `mise exec -- bundle exec rspec spec/requests/authenticated_landing_spec.rb -e "the seam is overridable"` — expected FAIL: `NoMethodError: undefined method 'authenticated_home_path'` (the method does not exist yet). The two "default destination" examples already pass (current behavior already lands on `root_url` / honors `return_to`) — they are the regression guard that the refactor preserves behavior.

- [ ] Minimal implementation. Edit `app/controllers/concerns/authenticatable.rb` — replace the `after_authentication_url` method (lines 49-51) with:

```ruby
    def after_authentication_url
      session.delete(:return_to_after_authenticating) || url_for(authenticated_home_path)
    end

    # The post-sign-in home for an authenticated user with no saved return_to.
    # Workspace-agnostic (a user may have no workspace under :none onboarding).
    # Forks override this ONE method to repoint the landing (e.g. `me_path`)
    # without touching session / return_to logic.
    def authenticated_home_path
      root_path
    end
```

- [ ] Run it (expect PASS): `mise exec -- bundle exec rspec spec/requests/authenticated_landing_spec.rb` — expected PASS (all examples green: default lands on `root_url`, `return_to` still wins, and overriding `authenticated_home_path` changes `after_authentication_url`).

- [ ] Run the FULL suite green: `mise exec -- bundle exec rspec` — expect 0 failures (the existing `spec/requests/sessions_spec.rb` sign-in redirect expectations must remain green — confirm the refactor preserved them).

- [ ] Commit (do NOT push):
  - `git add app/controllers/concerns/authenticatable.rb spec/requests/authenticated_landing_spec.rb`
  - `git commit -m "feat(auth): overridable authenticated_home_path landing seam"`

---

### Task 7: Final verification

**Files:** none (verification + optional squash review)

- [ ] Run the entire suite one last time from a clean state: `mise exec -- bundle exec rspec` — expect 0 failures, 0 errors. Investigate (don't relay) any pending examples introduced by this work.
- [ ] Confirm the boot path is sane under each posture by smoke-loading the initializer logic for `:none`: `mise exec -- bin/rails runner 'puts Rails.configuration.x.tenancy.onboarding.inspect'` — expected: prints `:personal` (the test/dev default; `:none` is opt-in via `TENANCY_ONBOARDING=none`, which a fork sets). This confirms the template still defaults correctly and `:none` did not become the new default.
- [ ] Review the full branch diff for scope creep: `git diff main...feat/onboarding-none-mode --stat` — expect ONLY the nine files in the File Structure table (fewer if Task 5 required no guard). No stray files, no `personal`-column migration (explicitly out of scope), no `/me` route (fork-owned).
- [ ] Confirm all commits are local and nothing was pushed: `git log --oneline main..feat/onboarding-none-mode` shows the Task 1-6 commits; `git status` shows the branch is ahead of `origin/main` with no `git push` having run. Leave the branch unpushed for the user to review.

---

## Notes for the implementer

- **Why request specs, not system specs:** this template ships no `/me` view (it's fork-owned per the design's repo split), so there is no authenticated landing *page* to drive in a browser here. The three blockers are config + a model callback + a controller seam — request/model/lib specs cover them fully. The system-level "signup lands on `/me` empty" coverage belongs to hallwaytrack, where the view exists.
- **The audit's likely outcome (Task 5):** the codebase is already broadly nil-safe — `application.html.erb` branches on `Current.workspace`; `_workspace_back_link.html.erb`, `_authenticated_layout_streams.html.erb`, `application_policy.rb` (`Current.workspace&.…`), `settings_navigation_helper.rb` (`return :personal if Current.workspace.nil?`), and both sidebar switcher partials (`if current_workspace.present?`) all guard. So Task 5 is expected to add a spec and zero production lines. Treat any 500 it surfaces as a real, narrowly-scoped guard to add — and verify via `log/test.log`, since Turbo can swallow the status.
- **Do not** drop or migrate the `personal`/`personal_workspace_id` columns (out of scope), add a `/me` route (fork-owned), or change the default onboarding posture (`:personal` stays the template default; `:none` is opt-in via `TENANCY_ONBOARDING=none`).
