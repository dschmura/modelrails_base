# Avatar/Crop UX Polish — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the modal the primary avatar management interface — no page navigation needed for common operations. Compact the crop UI layout.

**Architecture:** The profile page's avatar section is rewritten so clicking the avatar always opens a modal. The modal contains two modes (upload and crop) toggled by a lightweight Stimulus controller. The `_image_crop` partial gets a compact layout with preview inline alongside action buttons. The standalone crop page is unchanged but deprioritized.

**Tech Stack:** Rails 8.1, Stimulus, Turbo Streams, Cropper.js v1, Tailwind CSS 4.

**Spec:** `docs/superpowers/specs/2026-04-07-avatar-crop-ux-polish-design.md`

---

## File Structure

### Create

| File | Responsibility |
|------|---------------|
| `app/javascript/controllers/mode_switch_controller.js` | Toggles visibility between named content sections inside a container. Values: `mode` (string). Targets: `section`. Shows the section whose `data-mode` matches the current mode value, hides others. |

### Modify

| File | Change |
|------|--------|
| `app/views/account/profiles/edit.html.erb` | Rewrite avatar section: single click→modal for both states; single "Change" link; remove source radio buttons; render dual-mode modal (upload + crop) |
| `app/views/shared/_image_crop.html.erb` | Compact layout: remove header subtitle, move instruction text below slider as small muted line, preview inline with action buttons |
| `app/views/shared/_image_upload_modal.html.erb` | Add optional `avatar_sources` local for source selection inside modal |
| `app/views/account/avatars/update.turbo_stream.erb` | Add zoom slider, use compact layout matching standalone page |
| `app/views/workspaces/brandings/update.turbo_stream.erb` | Add zoom slider, use compact layout |
| `config/locales/en/image_crop.en.yml` | No changes needed — keys already correct |
| `config/locales/en/account.en.yml` | Remove `upload_new` key, keep `change` |
| `spec/system/avatar_spec.rb` | Update: always opens modal, single "Change" link, remove crop link assertion |
| `spec/system/image_crop_spec.rb` | Remove test asserting profile page links to crop page |

---

## Task 1: Create mode-switch Stimulus controller

**Files:**
- Create: `app/javascript/controllers/mode_switch_controller.js`

- [ ] **Step 1: Create the controller**

Create `app/javascript/controllers/mode_switch_controller.js`:

```javascript
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = { mode: { type: String, default: "default" } }
  static targets = ["section"]

  modeValueChanged() {
    this.sectionTargets.forEach(section => {
      section.hidden = section.dataset.mode !== this.modeValue
    })
  }

  switchTo(event) {
    this.modeValue = event.params.mode
  }
}
```

- [ ] **Step 2: Commit**

```bash
mise exec -- git add app/javascript/controllers/mode_switch_controller.js
mise exec -- git commit -m "feat: add mode-switch Stimulus controller for toggling content sections"
```

---

## Task 2: Compact the _image_crop partial layout

**Files:**
- Modify: `app/views/shared/_image_crop.html.erb`

- [ ] **Step 1: Rewrite the partial with compact layout**

Replace the entire contents of `app/views/shared/_image_crop.html.erb`:

```erb
<%# locals: (image:, aspect_ratio: 1.0, shape: :circle, save_url:, cancel_url:,
             upload_action: nil, remove_url: nil, remove_method: :delete,
             use_initials_url: nil, use_initials_params: nil,
             existing_crop: {}, title:, compact: false) -%>
<%
  preview_class = shape == :circle ? "rounded-full" : "rounded-md"
  has_secondary = upload_action.present? || use_initials_url.present? || remove_url.present?
%>

<% wrapper_class = compact ? "" : "max-w-2xl mx-auto px-4 py-12 sm:py-16" %>
<div class="<%= wrapper_class %>">

  <%# Card container — only rendered in non-compact (standalone page) mode %>
  <% if !compact %>
  <div class="bg-surface-overlay border border-border rounded-xl shadow-lg overflow-hidden">

    <%# Header %>
    <div class="px-6 py-4 border-b border-border">
      <h1 class="text-lg font-semibold text-text-heading"><%= title %></h1>
    </div>
  <% end %>

    <%# Crop form %>
    <%= form_with url: save_url, method: :patch do |f| %>
      <div data-controller="image-cropper"
           data-image-cropper-aspect-ratio-value="<%= aspect_ratio %>"
           data-image-cropper-existing-crop-value="<%= existing_crop.to_json %>"
           data-image-cropper-view-mode-value="1">

        <%# Crop viewport — Cropper.js takes over this container %>
        <div tabindex="0"
             role="application"
             aria-roledescription="<%= t('image_crop.crop_area_label') %>"
             aria-describedby="crop-description"
             data-action="keydown->image-cropper#handleKeydown"
             class="relative overflow-hidden bg-neutral-900
                    focus:outline-none focus:ring-2 focus:ring-interactive-focus focus:ring-inset
                    <%= compact ? 'rounded-lg' : '' %>"
             style="max-height: <%= compact ? '45vh' : '55vh' %>;">
          <%= image_tag url_for(image),
                data: { image_cropper_target: "image" },
                class: "block max-w-full",
                draggable: false,
                alt: title %>
        </div>
        <p id="crop-description" class="sr-only"><%= t("image_crop.crop_area_description") %></p>

        <%# Live region for screen reader announcements %>
        <div data-image-cropper-target="liveRegion"
             aria-live="polite"
             aria-atomic="true"
             class="sr-only">
        </div>

        <%# Zoom controls %>
        <div class="px-6 py-3 border-t border-border">
          <div class="flex items-center gap-4">
            <svg class="w-4 h-4 text-text-muted shrink-0" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor" aria-hidden="true">
              <path stroke-linecap="round" stroke-linejoin="round" d="M21 21l-5.197-5.197m0 0A7.5 7.5 0 105.196 5.196a7.5 7.5 0 0010.607 10.607zM13.5 10.5h-6" />
            </svg>
            <input type="range" min="0" max="100" value="0"
                   data-image-cropper-target="slider"
                   data-action="input->image-cropper#handleSlider"
                   aria-label="<%= t('image_crop.zoom') %>"
                   class="flex-1 h-1.5 rounded-full appearance-none bg-border-strong cursor-pointer
                          [&::-webkit-slider-thumb]:appearance-none [&::-webkit-slider-thumb]:w-4
                          [&::-webkit-slider-thumb]:h-4 [&::-webkit-slider-thumb]:rounded-full
                          [&::-webkit-slider-thumb]:bg-interactive [&::-webkit-slider-thumb]:cursor-pointer
                          [&::-webkit-slider-thumb]:shadow-sm [&::-webkit-slider-thumb]:border-2
                          [&::-webkit-slider-thumb]:border-white
                          [&::-moz-range-thumb]:w-4 [&::-moz-range-thumb]:h-4
                          [&::-moz-range-thumb]:rounded-full [&::-moz-range-thumb]:bg-interactive
                          [&::-moz-range-thumb]:border-2 [&::-moz-range-thumb]:border-white
                          [&::-moz-range-thumb]:cursor-pointer">
            <svg class="w-4 h-4 text-text-muted shrink-0" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor" aria-hidden="true">
              <path stroke-linecap="round" stroke-linejoin="round" d="M21 21l-5.197-5.197m0 0A7.5 7.5 0 105.196 5.196a7.5 7.5 0 0010.607 10.607zM10.5 7.5v6m3-3h-6" />
            </svg>
          </div>
          <div class="flex items-center justify-between mt-2">
            <p class="text-xs text-text-muted"><%= t("image_crop.instructions") %></p>
            <button type="button"
                    data-action="click->image-cropper#reset"
                    class="text-xs text-text-muted hover:text-text-body underline underline-offset-2
                           focus:outline-none focus:ring-2 focus:ring-interactive-focus rounded
                           min-h-[44px] inline-flex items-center px-1">
              <%= t("image_crop.reset") %>
            </button>
          </div>
        </div>

        <%# Hidden crop coordinates %>
        <input type="hidden" name="crop[x]" value="0" data-image-cropper-target="x">
        <input type="hidden" name="crop[y]" value="0" data-image-cropper-target="y">
        <input type="hidden" name="crop[w]" value="0" data-image-cropper-target="w">
        <input type="hidden" name="crop[h]" value="0" data-image-cropper-target="h">

        <%# Primary actions: Preview + Save + Skip — all in one row %>
        <div class="px-6 py-4 border-t border-border <%= compact ? '' : 'bg-surface-sunken/30' %>">
          <div class="flex items-center gap-4">
            <%# Compact preview inline with buttons %>
            <div data-image-cropper-target="preview"
                 class="shrink-0 overflow-hidden <%= preview_class %> border-2 border-border
                        w-12 h-12">
            </div>
            <div class="flex-1 flex flex-col sm:flex-row-reverse gap-2">
              <button type="submit"
                      data-action="click->image-cropper#save"
                      data-turbo-submits-with="<%= t('image_crop.saving') %>"
                      class="inline-flex items-center justify-center
                             min-h-[44px] px-8 py-2.5 rounded-md
                             text-sm font-semibold text-white
                             bg-interactive hover:bg-interactive-hover
                             focus:outline-none focus:ring-2 focus:ring-interactive-focus
                             sm:w-auto w-full">
                <%= t("image_crop.save") %>
              </button>
              <%= link_to t("image_crop.skip"), cancel_url,
                    class: "inline-flex items-center justify-center
                           min-h-[44px] px-6 py-2.5 rounded-md
                           text-sm font-medium text-text-muted hover:text-text-body
                           focus:outline-none focus:ring-2 focus:ring-interactive-focus
                           sm:w-auto w-full" %>
            </div>
          </div>
        </div>

      </div>
    <% end %>

    <%# Secondary actions — OUTSIDE the crop form to avoid nested form issues %>
    <% if has_secondary %>
      <div class="px-6 py-3 border-t border-border
                  flex flex-wrap items-center justify-center gap-x-4 gap-y-1">
        <% if upload_action.present? %>
          <button type="button"
                  data-action="<%= upload_action %>"
                  data-mode-switch-mode-param="upload"
                  class="text-sm text-text-muted hover:text-interactive underline underline-offset-2
                         min-h-[44px] inline-flex items-center
                         focus:outline-none focus:ring-2 focus:ring-interactive-focus rounded">
            <%= t("image_crop.upload_different") %>
          </button>
        <% end %>
        <% if use_initials_url.present? %>
          <%= button_to t("image_crop.use_initials"), use_initials_url,
                method: :patch,
                params: use_initials_params || {},
                class: "text-sm text-text-muted hover:text-interactive underline underline-offset-2
                       min-h-[44px] inline-flex items-center
                       focus:outline-none focus:ring-2 focus:ring-interactive-focus rounded" %>
        <% end %>
        <% if remove_url.present? %>
          <%= button_to t("image_crop.remove_photo"), remove_url,
                method: remove_method,
                params: { remove_image: "1" },
                class: "text-sm text-danger hover:text-danger/80 underline underline-offset-2
                       min-h-[44px] inline-flex items-center
                       focus:outline-none focus:ring-2 focus:ring-interactive-focus rounded",
                data: { turbo_confirm: t("image_crop.remove_confirm") } %>
        <% end %>
      </div>
    <% end %>

  <% if !compact %>
  </div>
  <% end %>
</div>
```

Key changes from previous version:
- New `compact:` local (default `false`) — when true, skips card wrapper and header for modal usage
- Header subtitle removed (was instruction text)
- Instruction text moved below zoom slider as small muted text, inline with Reset
- Preview moved inline with Save/Skip buttons in a single row (48px fixed circle)
- Separate "Preview:" section with borders eliminated
- Zoom section padding tightened (py-3 vs py-4)

- [ ] **Step 2: Update the standalone crop page to pass compact: false explicitly**

No change needed — `compact` defaults to `false`, so `crop.html.erb` continues to work without modification.

- [ ] **Step 3: Run existing specs**

```bash
mise exec -- bundle exec rspec spec/system/image_crop_spec.rb spec/requests/account/avatars_spec.rb --format progress
```

Expected: all pass (the partial interface is backwards-compatible — new `compact:` local has a default).

- [ ] **Step 4: Commit**

```bash
mise exec -- git add app/views/shared/_image_crop.html.erb
mise exec -- git commit -m "feat: compact crop layout — preview inline with buttons, instruction text below slider"
```

---

## Task 3: Rewrite profile page avatar section

**Files:**
- Modify: `app/views/account/profiles/edit.html.erb`

- [ ] **Step 1: Replace the avatar section (lines 7-82)**

Replace lines 7 through 82 of `app/views/account/profiles/edit.html.erb` (from `<%# Avatar preview and editor %>` through the closing `</div>` of that section) with:

```erb
  <%# Avatar management — modal-first %>
  <%
    has_avatar = @user.avatar.attached? && @user.avatar_source == "upload"
    existing_crop = has_avatar ? (@user.avatar.blob.metadata["crop"] || {}) : {}
    initial_mode = has_avatar ? "crop" : "upload"
  %>
  <div class="flex items-center gap-6 mt-8 mb-8"
       data-controller="modal mode-switch"
       data-mode-switch-mode-value="<%= initial_mode %>">

    <%# Avatar — always opens modal %>
    <button data-action="click->modal#open"
            type="button"
            class="shrink-0 rounded-full focus:outline-none focus:ring-2 focus:ring-offset-2
                   focus:ring-interactive-focus cursor-pointer group"
            aria-label="<%= t('account.avatars.edit.change') %>">
      <span id="user_avatar_profile" class="block relative">
        <%= avatar_for(@user, size: :xl) %>
        <span class="absolute inset-0 rounded-full bg-black/0 group-hover:bg-black/20
                     transition-colors flex items-center justify-center">
          <svg class="w-6 h-6 text-white opacity-0 group-hover:opacity-100 transition-opacity drop-shadow-md"
               fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor" aria-hidden="true">
            <path stroke-linecap="round" stroke-linejoin="round" d="M6.827 6.175A2.31 2.31 0 015.186 7.23c-.38.054-.757.112-1.134.175C2.999 7.58 2.25 8.507 2.25 9.574V18a2.25 2.25 0 002.25 2.25h15A2.25 2.25 0 0021.75 18V9.574c0-1.067-.75-1.994-1.802-2.169a47.865 47.865 0 00-1.134-.175 2.31 2.31 0 01-1.64-1.055l-.822-1.316a2.192 2.192 0 00-1.736-1.039 48.774 48.774 0 00-5.232 0 2.192 2.192 0 00-1.736 1.039l-.821 1.316z" />
            <path stroke-linecap="round" stroke-linejoin="round" d="M16.5 12.75a4.5 4.5 0 11-9 0 4.5 4.5 0 019 0zM18.75 10.5h.008v.008h-.008V10.5z" />
          </svg>
        </span>
      </span>
    </button>

    <div>
      <p class="text-lg font-semibold text-text-heading"><%= @user.full_name %></p>
      <button data-action="click->modal#open"
              type="button"
              class="text-sm text-interactive underline hover:no-underline mt-1
                     min-h-[44px] min-w-[44px]
                     focus:outline-none focus:ring-2 focus:ring-interactive-focus rounded">
        <%= t("account.avatars.edit.change") %>
      </button>
    </div>

    <%# Modal — contains both upload and crop modes %>
    <%= render "shared/modal", title: t("account.avatars.edit.title"), size: :lg do %>
      <%# Mode: crop — shown when avatar already uploaded %>
      <% if has_avatar %>
        <div data-mode-switch-target="section" data-mode="crop">
          <%= render "shared/image_crop",
                image: @user.avatar,
                aspect_ratio: 1.0,
                shape: :circle,
                save_url: save_crop_account_avatar_path,
                cancel_url: edit_account_profile_path,
                existing_crop: existing_crop,
                compact: true,
                upload_action: "click->mode-switch#switchTo",
                title: t("account.avatars.crop.title") %>
        </div>
      <% end %>

      <%# Mode: upload — shown when no avatar or user clicks "Upload different" %>
      <div data-mode-switch-target="section" data-mode="upload">
        <div data-controller="image-upload"
             data-image-upload-max-file-size-value="5"
             data-image-upload-accepted-types-value="image/png,image/jpeg,image/gif,image/webp"
             data-image-upload-auto-submit-value="true"
             data-error-invalid-type="<%= t('image_upload.errors.invalid_type') %>"
             data-error-file-too-large="<%= t('image_upload.errors.file_too_large', max_size: 5) %>"
             data-uploading-text="<%= t('image_upload.uploading') %>">

          <%# Validation error %>
          <div data-image-upload-target="error"
               role="alert"
               class="p-3 rounded-md bg-danger-surface text-danger text-sm border border-danger-border"
               hidden>
          </div>

          <%# Current image preview %>
          <% if @user.avatar.attached? %>
            <div data-image-upload-target="currentImage" class="flex justify-center mb-4">
              <%= image_tag url_for(@user.avatar),
                    class: "w-32 h-32 rounded-full object-cover",
                    alt: t("image_upload.current_alt") %>
            </div>
          <% end %>

          <%# Upload form %>
          <%= form_with url: account_avatar_path, method: :patch, multipart: true,
                        data: { image_upload_target: "form" },
                        class: "space-y-4" do |f| %>
            <input type="file"
                   name="avatar"
                   accept="image/png,image/jpeg,image/gif,image/webp"
                   class="sr-only"
                   data-image-upload-target="fileInput"
                   data-action="change->image-upload#handleFile">

            <div data-image-upload-target="uploadZone"
                 data-action="click->image-upload#selectFile keydown.enter->image-upload#selectFile keydown.space->image-upload#selectFile dragover->image-upload#handleDragOver dragleave->image-upload#handleDragLeave drop->image-upload#handleDrop"
                 class="flex flex-col items-center justify-center w-full py-8 px-4
                        border-2 border-dashed border-border-strong rounded-lg cursor-pointer
                        hover:border-interactive-focus hover:bg-surface-sunken/50
                        focus-within:ring-2 focus-within:ring-interactive-focus
                        transition-colors"
                 role="button"
                 tabindex="0"
                 aria-label="<%= t('image_upload.drop_zone') %>">
              <svg class="w-8 h-8 text-text-body mb-2" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor" aria-hidden="true">
                <path stroke-linecap="round" stroke-linejoin="round" d="M3 16.5v2.25A2.25 2.25 0 005.25 21h13.5A2.25 2.25 0 0021 18.75V16.5m-13.5-9L12 3m0 0l4.5 4.5M12 3v13.5" />
              </svg>
              <span class="text-sm font-medium text-text-body"><%= t("image_upload.drop_zone") %></span>
              <span class="text-xs text-text-muted mt-1">
                <%= t("image_upload.constraints", types: "PNG, JPEG, GIF, WEBP", max_size: 5) %>
              </span>
            </div>
          <% end %>

          <%# Remove current image %>
          <% if @user.avatar.attached? %>
            <div class="text-center mt-2">
              <%= button_to t("image_upload.remove"),
                    account_avatar_path,
                    method: :delete,
                    params: { remove_image: "1" },
                    class: "text-sm text-danger hover:text-danger/80
                           underline underline-offset-2
                           focus:outline-none focus:ring-2 focus:ring-interactive-focus
                           rounded min-h-[44px] px-2",
                    data: { turbo_confirm: t("image_upload.remove_confirm") } %>
            </div>
          <% end %>

          <%# Source selection — shown when multiple sources available %>
          <% if @user.available_avatar_sources.size > 1 %>
            <div class="pt-3 border-t border-border">
              <fieldset class="space-y-1">
                <legend class="text-xs font-medium text-text-muted mb-1">
                  <%= t("account.avatars.source_label") %>
                </legend>
                <% @user.available_avatar_sources.each do |source| %>
                  <% next if source == "upload" %>
                  <%= form_with url: account_avatar_path, method: :patch do |f| %>
                    <label class="flex items-center gap-3 min-h-[44px] cursor-pointer">
                      <input type="radio"
                             name="avatar_source"
                             value="<%= source %>"
                             <%= "checked" if @user.avatar_source == source %>
                             class="size-4 text-interactive focus:ring-2 focus:ring-interactive-focus"
                             onchange="this.form.requestSubmit()">
                      <span class="text-sm text-text-body">
                        <%= t("account.avatars.sources.#{source}") %>
                      </span>
                    </label>
                  <% end %>
                <% end %>
              </fieldset>
            </div>
          <% end %>
        </div>
      </div>
    <% end %>
  </div>
```

Also remove the source selection section that was previously below the avatar section (lines 84-108 in the original file — the `<% if @user.available_avatar_sources.size > 1 %>` fieldset block). It's now inside the modal.

- [ ] **Step 2: Run specs**

```bash
mise exec -- bundle exec rspec spec/system/avatar_spec.rb spec/system/image_crop_spec.rb spec/requests/account/avatars_spec.rb --format progress
```

Some specs will fail because they assert the old behavior (crop link, upload_new button). Fix those in the next task.

- [ ] **Step 3: Commit**

```bash
mise exec -- git add app/views/account/profiles/edit.html.erb app/views/shared/_image_crop.html.erb
mise exec -- git commit -m "feat: modal-first avatar management — single entry point, dual-mode modal"
```

---

## Task 4: Update the modal crop turbo_stream templates

**Files:**
- Modify: `app/views/account/avatars/update.turbo_stream.erb`
- Modify: `app/views/workspaces/brandings/update.turbo_stream.erb`

- [ ] **Step 1: Update the avatar update turbo_stream with compact layout**

Replace `app/views/account/avatars/update.turbo_stream.erb` with:

```erb
<%
  existing_crop = Current.user.avatar.blob.metadata["crop"] || {}
%>

<%= turbo_stream.replace "modal-body" do %>
  <div id="modal-body" class="px-6 py-4 overflow-y-auto flex-1">
    <%= render "shared/image_crop",
          image: Current.user.avatar,
          aspect_ratio: 1.0,
          shape: :circle,
          save_url: save_crop_account_avatar_path,
          cancel_url: edit_account_profile_path,
          existing_crop: existing_crop,
          compact: true,
          title: t("account.avatars.crop.title") %>
  </div>
<% end %>
```

This reuses the shared `_image_crop` partial in compact mode instead of duplicating the crop UI markup. The zoom slider, preview, and instruction text are all included via the partial.

- [ ] **Step 2: Update the workspace branding update turbo_stream**

Replace `app/views/workspaces/brandings/update.turbo_stream.erb` with:

```erb
<%
  existing_crop = @workspace.logo.blob.metadata["crop"] || {}
%>

<%= turbo_stream.replace "modal-body" do %>
  <div id="modal-body" class="px-6 py-4 overflow-y-auto flex-1">
    <%= render "shared/image_crop",
          image: @workspace.logo,
          aspect_ratio: 1.0,
          shape: :circle,
          save_url: save_crop_workspace_branding_path(@workspace),
          cancel_url: edit_workspace_branding_path(@workspace),
          existing_crop: existing_crop,
          compact: true,
          title: t("workspaces.brandings.crop.title") %>
  </div>
<% end %>
```

- [ ] **Step 3: Run request specs**

```bash
mise exec -- bundle exec rspec spec/requests/account/avatars_spec.rb spec/requests/workspaces/brandings_spec.rb --format progress
```

Expected: all pass.

- [ ] **Step 4: Commit**

```bash
mise exec -- git add app/views/account/avatars/update.turbo_stream.erb app/views/workspaces/brandings/update.turbo_stream.erb
mise exec -- git commit -m "feat: turbo_stream crop templates reuse shared partial in compact mode"
```

---

## Task 5: Update system and request specs

**Files:**
- Modify: `spec/system/avatar_spec.rb`
- Modify: `spec/system/image_crop_spec.rb`

- [ ] **Step 1: Update avatar system specs**

Replace `spec/system/avatar_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe "Avatar management", type: :system do
  let(:user) { create(:user, first_name: "Jane", last_name: "Doe") }

  def sign_in_via_form(user)
    visit new_session_path
    fill_in I18n.t("sessions.new.email_label"), with: user.email_address
    click_button I18n.t("sessions.new.continue")
    fill_in I18n.t("sessions.password_form.password_label"), with: "SecureP@ssw0rd123!"
    click_button I18n.t("sessions.password_form.submit")
    expect(page).to have_text(I18n.t("sessions.create.success"))
  end

  def dismiss_cookie_banner
    page.execute_script(<<~JS)
      const banner = document.querySelector('[data-biscuit-target="banner"]');
      if (banner) banner.remove();
    JS
  end

  it "displays initials avatar in profile page by default" do
    sign_in_via_form(user)
    visit edit_account_profile_path
    dismiss_cookie_banner
    expect(page).to have_css("span", text: "JD")
  end

  it "shows change avatar button on profile page" do
    sign_in_via_form(user)
    visit edit_account_profile_path
    dismiss_cookie_banner
    expect(page).to have_button(I18n.t("account.avatars.edit.change"))
  end

  it "opens avatar modal from profile page when no avatar" do
    sign_in_via_form(user)
    visit edit_account_profile_path
    dismiss_cookie_banner
    click_button I18n.t("account.avatars.edit.change")
    expect(page).to have_css("dialog[open]")
    expect(page).to have_text(I18n.t("account.avatars.edit.title"))
  end

  it "opens avatar modal with crop UI when avatar is uploaded" do
    user.avatar.attach(
      io: File.open(Rails.root.join("spec/fixtures/files/avatar.png")),
      filename: "avatar.png",
      content_type: "image/png"
    )
    user.update_columns(avatar_source: "upload")

    sign_in_via_form(user)
    visit edit_account_profile_path
    dismiss_cookie_banner
    click_button I18n.t("account.avatars.edit.change")
    expect(page).to have_css("dialog[open]")
    expect(page).to have_css("[data-controller='image-cropper']")
  end

  it "does not show source selection on profile page directly" do
    sign_in_via_form(user)
    visit edit_account_profile_path
    dismiss_cookie_banner
    # Source selection is now inside the modal, not on the page
    expect(page).not_to have_text(I18n.t("account.avatars.source_label"))
  end
end
```

- [ ] **Step 2: Update image crop system specs**

Remove the "profile page links to crop and upload" test from `spec/system/image_crop_spec.rb` since the profile page no longer has those links:

Delete this test block (around line 55-59):
```ruby
    it "profile page links to crop and upload when avatar exists" do
      visit edit_account_profile_path
      dismiss_banner
      expect(page).to have_link(I18n.t("account.avatars.crop.link"))
      expect(page).to have_button(I18n.t("account.avatars.edit.upload_new"))
    end
```

- [ ] **Step 3: Run all avatar-related specs**

```bash
mise exec -- bundle exec rspec spec/system/avatar_spec.rb spec/system/image_crop_spec.rb spec/requests/account/avatars_spec.rb spec/requests/workspaces/brandings_spec.rb --format progress
```

Expected: all pass.

- [ ] **Step 4: Commit**

```bash
mise exec -- git add spec/system/avatar_spec.rb spec/system/image_crop_spec.rb
mise exec -- git commit -m "test: update avatar specs for modal-first interaction"
```

---

## Task 6: Clean up locale keys

**Files:**
- Modify: `config/locales/en/account.en.yml`

- [ ] **Step 1: Remove the unused upload_new key**

In `config/locales/en/account.en.yml`, remove the `upload_new` key under `account.avatars.edit`:

Change:
```yaml
    avatars:
      edit:
        title: "Change avatar"
        change: "Change avatar"
        upload_new: "Upload new"
```

To:
```yaml
    avatars:
      edit:
        title: "Change avatar"
        change: "Change avatar"
```

- [ ] **Step 2: Verify no code references the removed key**

```bash
grep -r "upload_new" app/ spec/ --include="*.erb" --include="*.rb" -l
```

Expected: no matches.

- [ ] **Step 3: Commit**

```bash
mise exec -- git add config/locales/en/account.en.yml
mise exec -- git commit -m "chore: remove unused upload_new locale key"
```

---

## Task 7: Run full test suite and verify

**Files:** None (verification only)

- [ ] **Step 1: Run the complete test suite**

```bash
mise exec -- bundle exec rspec --format progress
```

Expected: all specs pass, zero failures.

- [ ] **Step 2: Manually verify the profile page flow**

1. Sign in, go to profile page
2. **No avatar:** Click avatar or "Change avatar" → modal opens with upload drop zone
3. Select file → auto-submit → modal transitions to crop UI with zoom slider
4. Adjust crop → click Save → modal closes, avatar updates on page and in nav header
5. Click avatar again → modal opens with crop UI showing current crop
6. Click "Upload a different image" → modal switches to upload drop zone
7. Select new file → auto-submit → modal transitions to crop UI with new image

- [ ] **Step 3: Verify compact layout**

- Preview circle is 48px, inline with Save/Skip buttons
- No "Preview:" label
- Instruction text is small muted text below zoom slider
- Zoom slider present in modal crop view
- No separate bordered preview section

- [ ] **Step 4: Commit any fixups**

If any issues were found during manual testing, fix and commit individually.
