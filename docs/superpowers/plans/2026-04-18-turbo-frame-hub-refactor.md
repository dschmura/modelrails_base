# Turbo Frame Hub Refactor Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Move the identity picker hub from JS state management to a server-rendered Turbo Frame, reducing `identity_picker_controller.js` from ~548 to ~250 lines while keeping the crop view client-side.

**Architecture:** The hub becomes a `<turbo-frame>` loaded via a new `hub` controller action. Source card clicks reload the frame via GET. Save & apply submits via native Turbo form. Remove photo uses `button_to DELETE`. The JS controller sheds all hub state management and keeps only crop/color/file/focus logic.

**Tech Stack:** Rails 8.1, Turbo Frames, Stimulus, Cropper.js v2, RSpec TDD

**Spec:** `docs/superpowers/specs/2026-04-17-turbo-frame-hub-refactor-design.md`

**Important:** All commands use `mise exec --` prefix.

---

## File Structure

### Files to create

- `app/views/shared/_identity_picker_hub.html.erb` — hub content partial (turbo frame)
- `app/javascript/controllers/auto_file_picker_controller.js` — declarative file picker trigger
- `app/views/account/avatars/destroy.turbo_stream.erb` — turbo stream for user avatar removal

### Files to modify

- `config/routes.rb` — add `hub` member route to avatar + branding resources
- `app/controllers/account/avatars_controller.rb` — add `hub` action, add `format.turbo_stream` to `destroy`
- `app/controllers/workspaces/brandings_controller.rb` — add `hub` action
- `app/views/shared/_identity_picker.html.erb` — slim to outer shell + turbo frame + crop view
- `app/views/account/profiles/edit.html.erb` — pass `hub_url` local
- `app/views/workspaces/brandings/edit.html.erb` — pass `hub_url` local
- `app/javascript/controllers/identity_picker_controller.js` — remove hub state management, add `onHubLoad`
- `spec/requests/account/avatars_spec.rb` — test `hub` action + turbo `destroy`
- `spec/requests/workspaces/brandings_spec.rb` — test `hub` action

### Files unchanged

- `app/javascript/controllers/image_cropper_controller.js` — crop view untouched
- `app/models/` — no model changes
- `app/policies/` — hub uses existing `update?` policy method

---

### Task 1: Routes + hub action for User avatars (TDD)

**Files:**
- Modify: `config/routes.rb`
- Modify: `app/controllers/account/avatars_controller.rb`
- Test: `spec/requests/account/avatars_spec.rb`

- [ ] **Step 1: Write failing request spec for hub action**

Add to `spec/requests/account/avatars_spec.rb` inside the authenticated context:

```ruby
describe "GET /account/avatar/hub" do
  it "renders the hub partial with the requested source" do
    get hub_account_avatar_path(source: "initials"),
      headers: { "Turbo-Frame" => "identity-picker-hub" }

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("identity-picker-hub")
  end

  it "falls back to user's current source for invalid source param" do
    get hub_account_avatar_path(source: "invalid"),
      headers: { "Turbo-Frame" => "identity-picker-hub" }

    expect(response).to have_http_status(:ok)
  end

  it "requires authentication" do
    sign_out
    get hub_account_avatar_path(source: "initials")
    expect(response).to redirect_to(new_session_path)
  end
end
```

Note: `sign_out` may need to be `reset!` or `cookies.delete(:session_id)` — match the existing auth teardown pattern in `spec/requests/account/avatars_spec.rb`. If no sign_out helper exists, test authentication by making a new request without the `sign_in` call in a separate context.

- [ ] **Step 2: Run test to verify it fails**

```bash
mise exec -- bundle exec rspec spec/requests/account/avatars_spec.rb -e "GET /account/avatar/hub" --format documentation
```

Expected: FAIL — route doesn't exist.

- [ ] **Step 3: Add the route**

In `config/routes.rb`, change line 24:

```ruby
resource :avatar, only: [ :update, :destroy ]
```

To:

```ruby
resource :avatar, only: [ :update, :destroy ] do
  get :hub, on: :member
end
```

Wait — `resource` (singular) doesn't have `member` blocks the same way `resources` does. For a singular resource, use:

```ruby
resource :avatar, only: [ :update, :destroy ] do
  get :hub
end
```

This creates `GET /account/avatar/hub` as `hub_account_avatar_path`.

- [ ] **Step 4: Add the hub action**

In `app/controllers/account/avatars_controller.rb`, add before the `update` method:

```ruby
def hub
  @user = Current.user
  authorize @user, policy_class: Account::AvatarPolicy

  @source = if params[:source].present? && @user.available_avatar_sources.include?(params[:source])
              params[:source]
            else
              @user.avatar_source
            end

  is_user = true
  has_image = @user.avatar.attached?
  current_hue = @user.primary_color || 210
  display_url = has_image ? url_for(@user.avatar) : nil
  gravatar_url = @user.gravatar_url(size: 256)

  render partial: "shared/identity_picker_hub",
    locals: {
      model: @user,
      form_url: account_avatar_path,
      hub_url: hub_account_avatar_path,
      current_source: @source,
      has_color_picker: true,
      available_sources: @user.available_avatar_sources,
      is_user: is_user,
      has_image: has_image,
      current_hue: current_hue,
      display_url: display_url,
      gravatar_url: gravatar_url,
      initials: @user.initials,
      hub_title: t("identity_picker.choose_profile_picture")
    },
    layout: false
end
```

- [ ] **Step 5: Create a minimal hub partial (placeholder)**

Create `app/views/shared/_identity_picker_hub.html.erb` with a minimal placeholder so the test passes:

```erb
<%# locals: (model:, form_url:, hub_url:, current_source:, has_color_picker:, available_sources:, is_user:, has_image:, current_hue:, display_url:, gravatar_url: nil, initials:, hub_title:) -%>
<turbo-frame id="identity-picker-hub">
  <p>Hub placeholder — source: <%= current_source %></p>
</turbo-frame>
```

This is a skeleton. Task 3 fills in the real content.

- [ ] **Step 6: Add `hub?` to AvatarPolicy**

The `hub` action calls `authorize @user, policy_class: Account::AvatarPolicy`. The policy needs a `hub?` method. In `app/policies/account/avatar_policy.rb`, add:

```ruby
def hub?
  user.present?
end
```

Or reuse `update?` by calling `authorize @user, :update?, policy_class: Account::AvatarPolicy` in the controller instead. Simpler: just use the `update?` check since viewing the hub is conceptually part of the update flow.

Change the authorize call in the hub action to:

```ruby
authorize @user, :update?, policy_class: Account::AvatarPolicy
```

This reuses the existing `update?` method — no new policy method needed.

- [ ] **Step 7: Run tests**

```bash
mise exec -- bundle exec rspec spec/requests/account/avatars_spec.rb -e "GET /account/avatar/hub" --format documentation
```

Expected: PASS.

- [ ] **Step 8: Run full suite**

```bash
mise exec -- bundle exec rspec spec/ --format progress
```

Expected: All pass (976+ examples).

- [ ] **Step 9: Commit**

```bash
git add config/routes.rb app/controllers/account/avatars_controller.rb app/views/shared/_identity_picker_hub.html.erb spec/requests/account/avatars_spec.rb
git commit -m "feat: add hub action for user avatar identity picker"
```

---

### Task 2: Routes + hub action for Workspace brandings (TDD)

**Files:**
- Modify: `config/routes.rb`
- Modify: `app/controllers/workspaces/brandings_controller.rb`
- Test: `spec/requests/workspaces/brandings_spec.rb`

- [ ] **Step 1: Write failing request spec**

Add to `spec/requests/workspaces/brandings_spec.rb` inside the authenticated context:

```ruby
describe "GET /workspaces/:workspace_slug/branding/hub" do
  it "renders the hub partial with the requested source" do
    get hub_workspace_branding_path(workspace),
      params: { source: "initials" },
      headers: { "Turbo-Frame" => "identity-picker-hub" }

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("identity-picker-hub")
  end

  it "falls back to workspace's current source for invalid source param" do
    get hub_workspace_branding_path(workspace),
      params: { source: "invalid" },
      headers: { "Turbo-Frame" => "identity-picker-hub" }

    expect(response).to have_http_status(:ok)
  end
end
```

- [ ] **Step 2: Run test — should fail**

```bash
mise exec -- bundle exec rspec spec/requests/workspaces/brandings_spec.rb -e "GET" --format documentation
```

- [ ] **Step 3: Add the route**

In `config/routes.rb`, change line 44:

```ruby
resource :branding, only: [ :edit, :update, :destroy ]
```

To:

```ruby
resource :branding, only: [ :edit, :update, :destroy ] do
  get :hub
end
```

- [ ] **Step 4: Add the hub action**

In `app/controllers/workspaces/brandings_controller.rb`, add before `update`:

```ruby
def hub
  authorize @workspace, policy_class: Workspaces::BrandingPolicy

  @source = if params[:source].present? && @workspace.available_logo_sources.include?(params[:source])
              params[:source]
            else
              @workspace.logo_source
            end

  is_user = false
  has_image = @workspace.logo.attached?
  current_hue = @workspace.primary_color || 210
  display_url = has_image ? url_for(@workspace.logo) : nil

  render partial: "shared/identity_picker_hub",
    locals: {
      model: @workspace,
      form_url: workspace_branding_path(@workspace),
      hub_url: hub_workspace_branding_path(@workspace),
      current_source: @source,
      has_color_picker: true,
      available_sources: @workspace.available_logo_sources,
      is_user: is_user,
      has_image: has_image,
      current_hue: current_hue,
      display_url: display_url,
      gravatar_url: nil,
      initials: @workspace.initials,
      hub_title: t("identity_picker.choose_workspace_logo")
    },
    layout: false
end
```

Use `:update?` for authorization (same as Task 1): `authorize @workspace, :update?, policy_class: Workspaces::BrandingPolicy`.

- [ ] **Step 5: Run tests**

```bash
mise exec -- bundle exec rspec spec/requests/workspaces/brandings_spec.rb -e "GET" --format documentation
```

Expected: PASS.

- [ ] **Step 6: Run full suite**

```bash
mise exec -- bundle exec rspec spec/ --format progress
```

- [ ] **Step 7: Commit**

```bash
git add config/routes.rb app/controllers/workspaces/brandings_controller.rb spec/requests/workspaces/brandings_spec.rb
git commit -m "feat: add hub action for workspace branding identity picker"
```

---

### Task 3: Build the hub partial with full content

**Files:**
- Modify: `app/views/shared/_identity_picker_hub.html.erb` (replace placeholder)

- [ ] **Step 1: Write the full hub partial**

Replace the placeholder `_identity_picker_hub.html.erb` with the full content. This is the hub view extracted from the current `_identity_picker.html.erb` (lines 47-242), adapted for Turbo Frames:

```erb
<%# locals: (model:, form_url:, hub_url:, current_source:, has_color_picker:, available_sources:, is_user:, has_image:, current_hue:, display_url:, gravatar_url: nil, initials:, hub_title:) -%>
<turbo-frame id="identity-picker-hub"
             data-action="turbo:frame-load->identity-picker#onHubLoad"
             data-modal-size="lg"
             data-modal-title="<%= hub_title %>">

  <%# Large preview — server renders the correct one based on current_source %>
  <div class="flex flex-col items-center py-6">
    <% if current_source == "upload" && has_image && display_url %>
      <%# Photo preview (clickable to crop) %>
      <button type="button"
              data-action="click->identity-picker#openCrop"
              data-identity-picker-target="photoPreview"
              aria-label="<%= t('identity_picker.edit_photo') %>"
              class="relative w-32 h-32 rounded-full overflow-hidden
                     group cursor-pointer
                     focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-interactive-focus">
        <%= image_tag display_url, class: "w-full h-full object-cover", alt: "" %>
        <span class="absolute inset-0 bg-black/0 group-hover:bg-black/30
                     flex items-center justify-center transition-colors">
          <%= icon(:pencil, size: :md,
                class: "text-white opacity-0 group-hover:opacity-100 transition-opacity drop-shadow-md") %>
        </span>
      </button>
    <% elsif current_source == "gravatar" && gravatar_url %>
      <%# Gravatar preview %>
      <%= image_tag gravatar_url,
            class: "w-32 h-32 rounded-full object-cover",
            alt: "",
            loading: "lazy" %>
    <% else %>
      <%# Initials preview (default) %>
      <div class="w-32 h-32 rounded-full flex items-center justify-center text-3xl font-semibold text-white"
           style="background-color: oklch(0.35 0.2 <%= current_hue %>)">
        <%= initials %>
      </div>
    <% end %>

    <span class="text-xs text-text-muted mt-2 uppercase tracking-wider">
      <%= t("identity_picker.preview") %>
    </span>
    <% last_changed = if is_user && model.avatar.attached?
                         model.avatar.blob.created_at
                       elsif !is_user && model.logo.attached?
                         model.logo.blob.created_at
                       end %>
    <% if last_changed %>
      <span class="text-xs text-text-muted mt-1">
        <%= t("identity_picker.last_updated", time: time_ago_in_words(last_changed)) %>
      </span>
    <% end %>
  </div>

  <%# Source selection %>
  <p class="text-sm text-text-muted mb-3"><%= t("identity_picker.choose_source") %></p>

  <%# Source cards as links (reload the turbo frame with new source) %>
  <div class="space-y-2" role="radiogroup" aria-label="<%= t('identity_picker.source_label') %>">
    <% if available_sources.include?("upload") %>
      <%= link_to url_for(action: :hub, source: "upload"),
            data: { turbo_frame: "identity-picker-hub" },
            role: "radio",
            "aria-checked": current_source == "upload",
            class: "flex items-center gap-4 p-4 rounded-lg border-2 cursor-pointer
                    hover:bg-surface-sunken/50 transition-all
                    #{current_source == 'upload' ? 'border-interactive bg-interactive/5' : 'border-border'}" do %>
        <%= icon(:camera, size: :lg, class: "text-text-muted shrink-0") %>
        <div class="flex-1 min-w-0">
          <span class="block text-sm font-medium text-text-heading">
            <%= t("identity_picker.sources.upload.title") %>
          </span>
          <span class="block text-xs text-text-muted">
            <%= t("identity_picker.sources.upload.description") %>
          </span>
        </div>
        <span class="size-4 rounded-full border-2 shrink-0
                     <%= current_source == 'upload' ? 'border-interactive bg-interactive' : 'border-border-strong' %>"></span>
      <% end %>
    <% end %>

    <% if available_sources.include?("gravatar") %>
      <%= link_to url_for(action: :hub, source: "gravatar"),
            data: { turbo_frame: "identity-picker-hub" },
            role: "radio",
            "aria-checked": current_source == "gravatar",
            class: "flex items-center gap-4 p-4 rounded-lg border-2 cursor-pointer
                    hover:bg-surface-sunken/50 transition-all
                    #{current_source == 'gravatar' ? 'border-interactive bg-interactive/5' : 'border-border'}" do %>
        <%= icon(:globe_alt, size: :lg, class: "text-text-muted shrink-0") %>
        <div class="flex-1 min-w-0">
          <span class="block text-sm font-medium text-text-heading">
            <%= t("identity_picker.sources.gravatar.title") %>
          </span>
          <span class="block text-xs text-text-muted">
            <%= t("identity_picker.sources.gravatar.description") %>
          </span>
        </div>
        <span class="size-4 rounded-full border-2 shrink-0
                     <%= current_source == 'gravatar' ? 'border-interactive bg-interactive' : 'border-border-strong' %>"></span>
      <% end %>
    <% end %>

    <% if available_sources.include?("initials") %>
      <%= link_to url_for(action: :hub, source: "initials"),
            data: { turbo_frame: "identity-picker-hub" },
            role: "radio",
            "aria-checked": current_source == "initials",
            class: "flex items-center gap-4 p-4 rounded-lg border-2 cursor-pointer
                    hover:bg-surface-sunken/50 transition-all
                    #{current_source == 'initials' ? 'border-interactive bg-interactive/5' : 'border-border'}" do %>
        <span class="w-10 h-10 rounded-full flex items-center justify-center text-xs font-semibold text-white shrink-0"
              style="background-color: oklch(0.35 0.2 <%= current_hue %>)">
          <%= initials %>
        </span>
        <div class="flex-1 min-w-0">
          <span class="block text-sm font-medium text-text-heading">
            <%= t("identity_picker.sources.initials.title") %>
          </span>
          <span class="block text-xs text-text-muted">
            <%= t("identity_picker.sources.initials.description") %>
          </span>
        </div>
        <span class="size-4 rounded-full border-2 shrink-0
                     <%= current_source == 'initials' ? 'border-interactive bg-interactive' : 'border-border-strong' %>"></span>
      <% end %>
    <% end %>
  </div>

  <%# Color picker panel (visible only when Initials is selected + has_color_picker) %>
  <% if has_color_picker && current_source == "initials" %>
    <div class="p-4 rounded-lg border border-border space-y-3 mt-4"
         data-controller="identity-picker">
      <div class="flex items-center justify-between">
        <span class="text-sm font-medium text-text-heading">
          <%= t("identity_picker.color_label") %>
        </span>
        <span class="text-xs font-mono text-text-muted"
              data-identity-picker-target="colorHex">
          <%= t("identity_picker.initial_color_name") %>
        </span>
      </div>
      <input type="range" min="0" max="360" step="1"
             value="<%= current_hue %>"
             data-identity-picker-target="colorSlider"
             data-action="input->identity-picker#handleColorChange"
             aria-label="<%= t('identity_picker.color_aria_label') %>"
             aria-valuemin="0" aria-valuemax="360"
             aria-valuenow="<%= current_hue %>"
             class="w-full h-3 rounded-full appearance-none cursor-pointer
                    [&::-webkit-slider-thumb]:appearance-none
                    [&::-webkit-slider-thumb]:w-5 [&::-webkit-slider-thumb]:h-5
                    [&::-webkit-slider-thumb]:rounded-full
                    [&::-webkit-slider-thumb]:bg-white
                    [&::-webkit-slider-thumb]:border-2 [&::-webkit-slider-thumb]:border-border-strong
                    [&::-webkit-slider-thumb]:shadow-md
                    [&::-webkit-slider-thumb]:cursor-pointer"
             style="background: linear-gradient(to right,
               oklch(0.35 0.2 0),
               oklch(0.35 0.2 60),
               oklch(0.35 0.2 120),
               oklch(0.35 0.2 180),
               oklch(0.35 0.2 240),
               oklch(0.35 0.2 300),
               oklch(0.35 0.2 360));">
    </div>
  <% end %>

  <%# Save form — submits via native Turbo (breaks out of frame to target whole page) %>
  <%= form_with url: form_url, method: :patch,
        data: { turbo_frame: "_top" },
        class: "mt-4" do |f| %>
    <input type="hidden" name="avatar_source" value="<%= current_source %>">
    <input type="hidden" name="primary_color" value="<%= current_hue %>"
           data-identity-picker-target="colorField">
    <div class="pt-4">
      <%= f.submit t("identity_picker.save"), class: "w-full flex items-center justify-center gap-2" %>
    </div>
  <% end %>

  <%# Auto-open file picker when Photo is selected but no image exists %>
  <% if current_source == "upload" && !has_image %>
    <div data-controller="auto-file-picker"
         data-auto-file-picker-target-value="[data-identity-picker-target='fileInput']">
    </div>
  <% end %>
</turbo-frame>
```

**Key differences from the old hub:**
- Source cards are `link_to` with `data-turbo-frame`, not radio buttons with JS handlers
- Radio indicator is a styled `<span>` circle, not an `<input type="radio">`
- Color picker only renders when `current_source == "initials"` — no JS show/hide
- Preview only renders the active source — no hidden elements toggled by JS
- Save form uses `data: { turbo_frame: "_top" }` to break out of the frame
- Auto-file-picker controller element renders conditionally

- [ ] **Step 2: Run request specs to verify hub renders**

```bash
mise exec -- bundle exec rspec spec/requests/account/avatars_spec.rb -e "GET /account/avatar/hub" --format documentation
```

Expected: PASS.

- [ ] **Step 3: Commit**

```bash
git add app/views/shared/_identity_picker_hub.html.erb
git commit -m "feat: build full hub partial with source cards, preview, and color picker"
```

---

### Task 4: Create auto_file_picker_controller.js

**Files:**
- Create: `app/javascript/controllers/auto_file_picker_controller.js`

- [ ] **Step 1: Create the controller**

Create `app/javascript/controllers/auto_file_picker_controller.js`:

```javascript
import { Controller } from "@hotwired/stimulus"

// Declarative file picker trigger. When this controller connects (rendered
// by the server when Photo is selected with no image), it clicks the hidden
// file input to open the native OS file dialog.
export default class extends Controller {
  static values = { target: String }

  connect() {
    const input = document.querySelector(this.targetValue)
    if (input) setTimeout(() => input.click(), 0)
  }
}
```

- [ ] **Step 2: Commit**

```bash
git add app/javascript/controllers/auto_file_picker_controller.js
git commit -m "feat: add auto_file_picker_controller for declarative file picker trigger"
```

---

### Task 5: Add turbo_stream to AvatarsController#destroy

**Files:**
- Modify: `app/controllers/account/avatars_controller.rb`
- Create: `app/views/account/avatars/destroy.turbo_stream.erb`
- Test: `spec/requests/account/avatars_spec.rb`

- [ ] **Step 1: Write failing test**

Add to `spec/requests/account/avatars_spec.rb`:

```ruby
describe "DELETE /account/avatar (turbo_stream)" do
  before do
    user.avatar.attach(
      io: File.open(Rails.root.join("spec/fixtures/files/avatar.png")),
      filename: "avatar.png",
      content_type: "image/png"
    )
    user.update!(avatar_source: "upload")
  end

  it "responds with turbo stream when requested" do
    delete account_avatar_path,
      headers: { "Accept" => "text/vnd.turbo-stream.html" }

    expect(response).to have_http_status(:success)
    expect(response.media_type).to eq("text/vnd.turbo-stream.html")
    user.reload
    expect(user.avatar).not_to be_attached
    expect(user.avatar_source).to eq("initials")
  end
end
```

- [ ] **Step 2: Run test — should fail**

```bash
mise exec -- bundle exec rspec spec/requests/account/avatars_spec.rb -e "DELETE /account/avatar" --format documentation
```

- [ ] **Step 3: Update destroy action**

In `app/controllers/account/avatars_controller.rb`, replace the `destroy` method:

```ruby
def destroy
  authorize Current.user, policy_class: Account::AvatarPolicy
  Current.user.avatar.purge
  Current.user.avatar_original.purge if Current.user.avatar_original.attached?
  Current.user.update!(avatar_source: "initials")

  respond_to do |format|
    format.turbo_stream
    format.html { redirect_to edit_account_profile_path, notice: t(".success") }
  end
end
```

- [ ] **Step 4: Create the turbo stream template**

Create `app/views/account/avatars/destroy.turbo_stream.erb`:

```erb
<%= turbo_stream.replace "user_avatar_profile" do %>
  <span id="user_avatar_profile">
    <%= avatar_for(Current.user, size: :xl) %>
  </span>
<% end %>

<%= turbo_stream.replace "user_avatar_header" do %>
  <span id="user_avatar_header"><%= avatar_for(Current.user, size: :md) %></span>
<% end %>

<%= turbo_stream.append "modal-body" do %>
  <div data-controller="modal-closer"></div>
<% end %>

<%= turbo_stream.append "toast-pills" do %>
  <%= render "shared/toast_pill", type: :success, message: t("account.avatars.destroy.success") %>
<% end %>
```

- [ ] **Step 5: Run tests**

```bash
mise exec -- bundle exec rspec spec/requests/account/avatars_spec.rb -e "DELETE" --format documentation
```

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add app/controllers/account/avatars_controller.rb app/views/account/avatars/destroy.turbo_stream.erb spec/requests/account/avatars_spec.rb
git commit -m "feat: add turbo_stream response to AvatarsController#destroy"
```

---

### Task 6: Rewrite the outer shell partial

**Files:**
- Modify: `app/views/shared/_identity_picker.html.erb`
- Modify: `app/views/account/profiles/edit.html.erb`
- Modify: `app/views/workspaces/brandings/edit.html.erb`

This is the biggest ERB change. The outer shell partial shrinks from ~439 lines to ~120 lines. It keeps: the controller wrapper, file input, ARIA region, turbo frame for the hub, and the crop view section.

- [ ] **Step 1: Rewrite the outer shell partial**

Replace the ENTIRE content of `app/views/shared/_identity_picker.html.erb` with:

```erb
<%# locals: (model:, form_url:, hub_url:, hub_title:, crop_title:) -%>
<%
  is_user = model.is_a?(User)
  has_image = is_user ? model.avatar.attached? : model.logo.attached?

  # URL for re-crop — use original so quality isn't progressively degraded
  original_url = if is_user && model.avatar_original.attached?
                   url_for(model.avatar_original)
                 elsif !is_user && model.logo_original.attached?
                   url_for(model.logo_original)
                 else
                   is_user && model.avatar.attached? ? url_for(model.avatar) : (!is_user && model.logo.attached? ? url_for(model.logo) : nil)
                 end
%>

<div data-controller="identity-picker"
     data-identity-picker-form-url-value="<%= form_url %>"
     data-identity-picker-has-image-value="<%= has_image %>"
     data-identity-picker-crop-title-value="<%= crop_title %>">

  <%# Hidden file input — triggered programmatically by crop flow %>
  <input type="file"
         accept="image/png,image/jpeg,image/gif,image/webp"
         class="sr-only"
         data-identity-picker-target="fileInput"
         data-action="change->identity-picker#handleFileSelected"
         aria-label="<%= t('identity_picker.select_file') %>">

  <%# ARIA live region for announcements %>
  <div aria-live="polite" class="sr-only"></div>

  <%# ═══════ HUB VIEW (Turbo Frame — server-rendered) ═══════ %>
  <turbo-frame id="identity-picker-hub"
               src="<%= hub_url %>"
               loading="lazy">
    <%# Content loaded from the hub controller action %>
    <div class="flex items-center justify-center py-12">
      <span class="text-text-muted text-sm"><%= t("identity_picker.preview") %></span>
    </div>
  </turbo-frame>

  <%# ═══════ CROP VIEW (JS-managed — stays client-side) ═══════ %>
  <div data-identity-picker-target="cropSection" hidden>
    <%# Header: back link + crop title %>
    <div class="flex items-center justify-between mb-4">
      <button type="button"
              data-action="click->identity-picker#backToHub"
              class="inline-flex items-center gap-1.5 text-sm text-interactive
                     hover:text-interactive-hover
                     min-h-[44px] px-2 rounded
                     focus:outline-none focus:ring-2 focus:ring-interactive-focus">
        <%= icon(:arrow_left, size: :sm) %>
        <%= t("identity_picker.back_to_source") %>
      </button>
      <h3 class="text-lg font-semibold text-text-heading">
        <%= t("identity_picker.crop_title") %>
      </h3>
    </div>

    <%# Two-column grid: crop viewport (left) + controls (right) %>
    <div class="crop-view-grid"
         data-controller="image-cropper"
         data-image-cropper-aspect-ratio-value="1"
         data-action="keydown->image-cropper#handleKeydown image-cropper:cropChanged->identity-picker#updateCropPreview"
         tabindex="0"
         aria-label="<%= t('identity_picker.crop_area_label') %>">

      <%# ── Left column: Crop viewport ── %>
      <div>
        <div class="cropper-container rounded-lg"
             data-image-cropper-target="container">
          <% if has_image && original_url %>
            <%= image_tag original_url, class: "max-w-full", alt: "" %>
          <% else %>
            <img src="" class="max-w-full" alt="">
          <% end %>
          <%# Dimension badge %>
          <div class="crop-dimension-badge"
               data-image-cropper-target="dimensionBadge"
               aria-hidden="true">
            &mdash;
          </div>
        </div>

        <%# ARIA live region %>
        <div data-image-cropper-target="liveRegion"
             aria-live="polite" class="sr-only"></div>

        <%# Hint text below crop area %>
        <p class="text-sm text-text-muted text-center mt-2">
          <%= t("identity_picker.crop_hint") %>
        </p>
      </div>

      <%# ── Right column: Controls ── %>
      <div class="space-y-5">
        <%# Preview section %>
        <div>
          <span class="block text-xs uppercase tracking-wider text-text-muted mb-3">
            <%= t("identity_picker.preview") %>
          </span>
          <div class="flex items-center gap-3">
            <div class="w-16 h-16 rounded-full bg-surface-sunken overflow-hidden shrink-0"
                 aria-hidden="true">
              <img src="" alt=""
                   class="w-full h-full object-cover"
                   data-identity-picker-target="cropPreview">
            </div>
            <div>
              <span class="block text-sm font-medium text-text-heading">
                <%= t("identity_picker.preview_title") %>
              </span>
              <span class="block text-xs text-text-muted">
                <%= t("identity_picker.preview_description") %>
              </span>
            </div>
          </div>
        </div>

        <%# Zoom slider with label and percentage %>
        <div>
          <div class="flex items-center justify-between mb-2">
            <span class="inline-flex items-center gap-1.5 text-sm font-medium text-text-heading">
              <%= t("identity_picker.zoom_label") %>
            </span>
            <span class="text-sm font-medium text-interactive"
                  data-image-cropper-target="zoomPercent">
              100%
            </span>
          </div>
          <input type="range" min="0" max="100" value="0"
                 data-image-cropper-target="slider"
                 data-action="input->image-cropper#handleSlider"
                 aria-label="<%= t('identity_picker.zoom_aria_label') %>"
                 aria-valuemin="0" aria-valuemax="100" aria-valuenow="0"
                 class="w-full h-2 rounded-full appearance-none cursor-pointer
                        bg-border
                        [&::-webkit-slider-thumb]:appearance-none
                        [&::-webkit-slider-thumb]:w-4 [&::-webkit-slider-thumb]:h-4
                        [&::-webkit-slider-thumb]:rounded-full
                        [&::-webkit-slider-thumb]:bg-white
                        [&::-webkit-slider-thumb]:border-2 [&::-webkit-slider-thumb]:border-border-strong
                        [&::-webkit-slider-thumb]:shadow">
        </div>

        <%# Reset button %>
        <button type="button"
                data-action="click->identity-picker#resetCrop"
                class="w-full inline-flex items-center justify-center gap-2 px-4 py-2
                       text-sm font-medium text-text-body
                       border border-border rounded-lg
                       hover:bg-surface-sunken
                       focus:outline-none focus:ring-2 focus:ring-interactive-focus
                       min-h-[44px]">
          <%= icon(:arrow_path, size: :sm) %>
          <%= t("identity_picker.reset_crop") %>
        </button>

        <%# GIF warning %>
        <div data-identity-picker-target="gifWarning"
             class="flex items-start gap-2.5 p-3 rounded-lg bg-warning-surface text-warning text-sm"
             hidden>
          <%= icon(:exclamation_triangle, size: :sm, class: "shrink-0 mt-0.5") %>
          <p><%= t("identity_picker.gif_static_warning") %></p>
        </div>

        <%# Info banner %>
        <div class="flex items-start gap-2.5 p-3 rounded-lg bg-info-subtle text-info text-sm">
          <%= icon(:information_circle, size: :sm, class: "shrink-0 mt-0.5") %>
          <p><%= t("identity_picker.image_quality_tip") %></p>
        </div>
      </div>

      <%# ── Footer: spans both columns ── %>
      <div class="crop-view-footer flex flex-col gap-3 pt-4 border-t border-border">
        <%# Primary row: Cancel + Save crop %>
        <div class="flex items-center justify-end gap-3">
          <button type="button"
                  data-action="click->identity-picker#backToHub"
                  class="inline-flex items-center justify-center px-4 py-2
                         text-sm font-medium text-text-body
                         border border-border rounded-lg
                         hover:bg-surface-sunken
                         focus:outline-none focus:ring-2 focus:ring-interactive-focus
                         min-h-[44px]">
            <%= t("identity_picker.cancel") %>
          </button>
          <button type="button"
                  data-action="click->identity-picker#saveCrop"
                  class="inline-flex items-center gap-2 px-5 py-2 rounded-lg
                         bg-interactive text-text-on-interactive font-medium text-sm
                         hover:bg-interactive-hover
                         focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-interactive-focus
                         min-h-[44px]">
            <%= t("identity_picker.save_crop") %>
          </button>
        </div>
        <%# Secondary row: Upload new (left) + Remove photo (right) %>
        <div class="flex items-center justify-between">
          <button type="button"
                  data-action="click->identity-picker#openFilePicker"
                  class="inline-flex items-center gap-1.5 text-sm text-interactive
                         hover:text-interactive-hover
                         min-h-[44px] px-2 rounded
                         focus:outline-none focus:ring-2 focus:ring-interactive-focus">
            <%= icon(:arrow_up_tray, size: :sm) %>
            <%= t("identity_picker.upload_new") %>
          </button>
          <%= button_to t("identity_picker.remove_photo"),
                form_url,
                method: :delete,
                data: { turbo_frame: "_top" },
                class: "inline-flex items-center gap-1.5 text-sm text-danger
                       hover:text-danger/80
                       min-h-[44px] px-2 rounded
                       focus:outline-none focus:ring-2 focus:ring-interactive-focus" %>
        </div>
      </div>
    </div>
  </div>
</div>
```

**Key changes from old partial:**
- No more `mode-switch` controller — crop visibility managed by `identity-picker` target (`cropSection`)
- Hub is a `<turbo-frame>` with `src=` for lazy loading
- Removed all hub HTML (moved to `_identity_picker_hub.html.erb`)
- Crop view is mostly unchanged but uses `data-identity-picker-target="cropSection"` instead of `data-mode-switch-target="section"`
- "Remove photo" is now `button_to DELETE` instead of a JS `removePhoto()` call
- Dropped `mode-switch` controller entirely — `identity-picker` manages the one mode toggle (show/hide crop)
- Locals simplified: no more `available_sources`, `has_color_picker` (hub handles those)

- [ ] **Step 2: Update profiles/edit.html.erb to pass hub_url**

In `app/views/account/profiles/edit.html.erb`, change the identity picker render:

```erb
<%= render "shared/identity_picker",
      model: @user,
      form_url: account_avatar_path,
      hub_url: hub_account_avatar_path,
      hub_title: t("identity_picker.choose_profile_picture"),
      crop_title: t("identity_picker.adjust_profile_picture") %>
```

Remove `available_sources:` and `has_color_picker:` — the hub action handles those.

- [ ] **Step 3: Update brandings/edit.html.erb to pass hub_url**

In `app/views/workspaces/brandings/edit.html.erb`, change the identity picker render:

```erb
<%= render "shared/identity_picker",
      model: @workspace,
      form_url: workspace_branding_path(@workspace),
      hub_url: hub_workspace_branding_path(@workspace),
      hub_title: t("identity_picker.choose_workspace_logo"),
      crop_title: t("identity_picker.adjust_workspace_logo") %>
```

Remove `available_sources:` and `has_color_picker:`.

- [ ] **Step 4: Run full suite**

```bash
mise exec -- bundle exec rspec spec/ --format progress
```

Expected: Some system specs may fail because they look for radio buttons (now links) or reference removed Stimulus targets. Note which specs fail but don't fix them yet — Task 7 handles the JS controller, and Task 8 fixes tests.

- [ ] **Step 5: Commit**

```bash
git add app/views/shared/_identity_picker.html.erb app/views/account/profiles/edit.html.erb app/views/workspaces/brandings/edit.html.erb
git commit -m "feat: rewrite identity picker outer shell with Turbo Frame hub"
```

---

### Task 7: Simplify identity_picker_controller.js

**Files:**
- Modify: `app/javascript/controllers/identity_picker_controller.js`

This is the biggest JS change. The controller drops from ~548 lines to ~250 by removing all hub state management.

- [ ] **Step 1: Rewrite the controller**

Replace the ENTIRE content of `app/javascript/controllers/identity_picker_controller.js`. The new controller keeps:
- `connect`/`disconnect` (Escape/X interception)
- `openCrop` (enter crop view)
- `saveCrop` (canvas blob export + fetch)
- `handleFileSelected` (file validation + crop transition)
- `handleColorChange` (live slider preview)
- `backToHub` (show hub, hide crop)
- `onHubLoad` (read modal size/title from hub frame data attributes)
- `updateCropPreview` (live crop preview)
- `resetCrop`, `openFilePicker`
- `_manageFocus`, `_announce`, `_releasePendingFile`, `_toggleGifWarning`

Removed:
- `selectSource`, `handleSourceChange`, `_selectSourceByValue` (server handles)
- `_updatePreview`, `_updateCardStyles`, `_updateContextualControls` (server handles)
- `_autoOpenForSource` (replaced by auto_file_picker_controller)
- `removePhoto` async fetch (`button_to DELETE` handles)
- `_saving` guard for removePhoto (Turbo disables button)
- `_switchMode` (replaced by simpler show/hide on `cropSection` target)
- `_toggleModalSize`, `_updateModalTitle` (replaced by `onHubLoad`)
- Targets: `sourceField`, `sourceCards`, `colorPanel`, `initialsPreview`, `photoPreview`, `gravPreview`, `form`

The engineer should read the current controller, understand what each method does, then write the new version keeping only the methods listed above. The new controller should be written as a complete replacement — do NOT try to selectively delete methods from the existing file, as the interconnections are too tangled.

Key new method — `onHubLoad`:

```javascript
// Called when the hub turbo frame loads/reloads.
// Reads modal size and title from the frame's data attributes.
onHubLoad(event) {
  const frame = event.target
  const size = frame.dataset.modalSize
  const title = frame.dataset.modalTitle

  const panel = this.element.closest("[data-modal-target='panel']")
  if (panel && size) {
    panel.classList.remove("max-w-2xl", "max-w-4xl")
    panel.classList.add(size === "lg" ? "max-w-2xl" : "max-w-4xl")
  }

  const dialog = this.element.closest("dialog")
  if (dialog && title) {
    const titleEl = dialog.querySelector("[id$='-title']")
    if (titleEl) titleEl.textContent = title
  }
}
```

Key change — `backToHub` now shows/hides the crop section target:

```javascript
backToHub() {
  this._releasePendingFile()
  if (this.hasCropSectionTarget) {
    this.cropSectionTarget.hidden = true
  }
  // Show the hub frame
  const hubFrame = this.element.querySelector("#identity-picker-hub")
  if (hubFrame) hubFrame.hidden = false

  // Reset modal size/title to hub values
  this.onHubLoad({ target: hubFrame })

  this._manageFocus("hub")
}
```

And `openCrop`/crop entry hides the hub frame and shows the crop section:

```javascript
_enterCropView() {
  const hubFrame = this.element.querySelector("#identity-picker-hub")
  if (hubFrame) hubFrame.hidden = true
  if (this.hasCropSectionTarget) {
    this.cropSectionTarget.hidden = false
  }
  // Set crop-specific modal size and title
  const panel = this.element.closest("[data-modal-target='panel']")
  if (panel) {
    panel.classList.remove("max-w-2xl")
    panel.classList.add("max-w-4xl")
  }
  const dialog = this.element.closest("dialog")
  if (dialog) {
    const titleEl = dialog.querySelector("[id$='-title']")
    if (titleEl) titleEl.textContent = this.cropTitleValue
  }
}
```

The `saveCrop` method simplifies significantly — after the fetch succeeds, just let the turbo stream response handle the UI update (it closes the modal, updates avatars, shows toast). No more `_switchMode("hub")`, `_updatePreview()`, etc.:

```javascript
// Success — turbo stream handles modal close, avatar updates, toast
const html = await response.text()
Turbo.renderStreamMessage(html)
this._releasePendingFile()
// No manual UI updates needed — turbo stream does it all
```

**Important:** Write the complete new controller file. Do NOT give a diff or partial instructions. The engineer needs to see the whole file to understand how the pieces fit together.

- [ ] **Step 2: Run full suite**

```bash
mise exec -- bundle exec rspec spec/ --format progress
```

Note which tests fail. The system specs that reference radio buttons, removed targets, or old source-selection patterns will need updating in Task 8.

- [ ] **Step 3: Commit**

```bash
git add app/javascript/controllers/identity_picker_controller.js
git commit -m "refactor: simplify identity_picker_controller to ~250 lines (Turbo Frame hub)"
```

---

### Task 8: Fix system specs for the new architecture

**Files:**
- Modify: `spec/system/account/profiles_spec.rb`
- Modify: `spec/system/workspaces/brandings_spec.rb`
- Modify: `spec/support/identity_picker_helpers.rb`

The system specs use helpers like `select_identity_source` (which clicks a `<label>` containing a radio button) and reference Stimulus targets that no longer exist. Update them for the link-based source cards.

- [ ] **Step 1: Update the `select_identity_source` helper**

In `spec/support/identity_picker_helpers.rb`, the current helper is:

```ruby
def select_identity_source(title)
  within("[data-identity-picker-target='sourceCards']") do
    find("label", text: title).click
  end
end
```

Source cards are now `<a>` links inside `<turbo-frame id="identity-picker-hub">`, not labels with radio buttons. Replace with:

```ruby
def select_identity_source(title)
  within("#identity-picker-hub") do
    click_link title
  end
  # Wait for the turbo frame to reload with the new source
  expect(page).to have_css("#identity-picker-hub", wait: 3)
end
```

- [ ] **Step 2: Update `wait_for_hub_view`**

The old helper waited for `data-mode="hub"`. Now the hub is a turbo frame that becomes visible when the crop section is hidden. Replace:

```ruby
def wait_for_hub_view
  expect(page).to have_css("#identity-picker-hub:not([hidden])", wait: 3)
end
```

- [ ] **Step 3: Run each system spec individually to identify remaining failures**

```bash
mise exec -- bundle exec rspec spec/system/account/profiles_spec.rb --format documentation
```

Fix failures one at a time. Common issues:
- Assertions on `[data-source='initials'].border-interactive` — links use the same classes but the attribute might be different. Update selectors.
- Assertions on `[data-identity-picker-target='colorPanel']` — color panel is now server-rendered conditionally, not toggled. Check for presence/absence differently.
- Assertions on `[data-identity-picker-target='initialsPreview']` — preview is now just a div inside the frame, not a targeted element.
- The keyboard nav spec (ArrowDown on radio group) — source cards are now links, not a radiogroup. This spec needs to be rewritten or removed since the navigation pattern changed.
- The double-click guard spec — may still work since `saveCrop` still uses `_saving`.

- [ ] **Step 4: Run workspace specs**

```bash
mise exec -- bundle exec rspec spec/system/workspaces/brandings_spec.rb --format documentation
```

Fix workspace-specific failures.

- [ ] **Step 5: Run full suite**

```bash
mise exec -- bundle exec rspec spec/ --format progress
```

Expected: All pass.

- [ ] **Step 6: Commit**

```bash
git add spec/
git commit -m "test: update system specs for Turbo Frame hub architecture"
```

---

### Task 9: Final verification

**Files:** None (verification only)

- [ ] **Step 1: Run full suite**

```bash
mise exec -- bundle exec rspec spec/ --format progress
```

Expected: 976+ examples, 0 failures.

- [ ] **Step 2: Run system specs with CI=true**

```bash
CI=true mise exec -- bundle exec rspec spec/system/ --format progress
```

Expected: All pass including axe accessibility audits.

- [ ] **Step 3: Count JS lines**

```bash
wc -l app/javascript/controllers/identity_picker_controller.js
```

Expected: ~250 lines (down from 548).

- [ ] **Step 4: Visual verification**

Start dev server and check:
1. Profile page → open modal → hub loads via turbo frame
2. Click Initials → frame reloads with initials preview + color picker
3. Click Photo → frame reloads; if no image, file picker opens automatically
4. Upload image → crop view → Save crop → modal closes, avatar updates
5. Re-open modal → click photo preview → crop view
6. Cancel/Escape → back to hub (modal stays open)
7. Save & apply → modal closes, avatar updates
8. Workspace branding → same flow
9. Remove photo from crop view → modal closes, avatar purged

- [ ] **Step 5: Verify line count reduction**

```bash
echo "Before: 987 lines (548 JS + 439 ERB)"
wc -l app/javascript/controllers/identity_picker_controller.js app/views/shared/_identity_picker.html.erb app/views/shared/_identity_picker_hub.html.erb app/javascript/controllers/auto_file_picker_controller.js
```

Expected: ~500 total (250 JS + 120 shell + 150 hub + 10 auto-picker) — down from 987.

---

## Self-Review

### Spec coverage

| Spec requirement | Task |
|---|---|
| New `hub` routes | Task 1, Task 2 |
| `hub` controller actions (User + Workspace) | Task 1, Task 2 |
| Hub partial with turbo frame, source cards as links | Task 3 |
| Auto file picker controller | Task 4 |
| `AvatarsController#destroy` turbo stream | Task 5 |
| Outer shell partial rewrite | Task 6 |
| JS controller simplification | Task 7 |
| System spec updates | Task 8 |
| Edge case: Remove Photo from crop view | Task 6 (button_to DELETE in crop footer) |
| Edge case: saveCrop → turbo stream handles post-save | Task 7 (saveCrop simplification) |
| Modal size/title via data attributes | Task 3 (data attrs on frame) + Task 7 (onHubLoad) |

### Placeholder scan

No TBD, TODO, or vague instructions. Task 7 instructs to write the complete controller (not a diff), which is the right approach for a rewrite.

### Type consistency

- `hub_url` — passed as local from profiles/brandings views → identity picker → turbo frame `src`
- `identity-picker-hub` — frame ID consistent across hub partial, outer shell, helpers
- `cropSection` target — used in outer shell and JS controller
- `onHubLoad` — defined in Task 7, wired via `data-action` in Task 3
- `auto-file-picker` controller — created in Task 4, rendered conditionally in Task 3
