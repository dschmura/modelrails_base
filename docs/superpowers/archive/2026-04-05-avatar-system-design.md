# Avatar System with Gravatar and Source Selection — Design Spec

## Problem

The current avatar implementation is minimal — a bare `has_one_attached :avatar` with a simple upload/destroy controller. There is no Gravatar integration, no source selection, no consistent avatar display helper, and no preview or cropping in the upload flow. The user menu renders avatar logic inline with duplicated markup.

## Solution

Build on the image upload modal (separate spec) to create an avatar-specific layer with:

1. **Gravatar integration** — Async check for Gravatar availability, cached on the User model
2. **Avatar source selection** — Users choose between uploaded image, Gravatar, or initials
3. **Avatar display helper** — `avatar_for(user, size:)` replaces inline avatar rendering throughout the app
4. **Profile page avatar editor** — Opens image upload modal with avatar-specific options

## Prerequisites

This spec depends on the Image Upload Modal spec being implemented first. The avatar editor uses the `_image_upload_modal.html.erb` partial with `crop: true, aspect_ratio: 1, max_width: 512, max_height: 512`.

## Architecture

### Database Migration

Single migration for the entire avatar feature:

```ruby
add_column :users, :avatar_source, :string, default: "initials"
add_column :users, :has_gravatar, :boolean, default: false
add_column :authentications, :avatar_url, :string
```

### User Model Changes

**New columns:**

- `avatar_source` — string enum: `"upload"`, `"gravatar"`, `"initials"`. Default: `"initials"`.
- `has_gravatar` — boolean, cached result of Gravatar check. Default: `false`.

**Validations:**

```ruby
validates :avatar_source, inclusion: { in: %w[upload gravatar initials] }
```

**Methods:**

```ruby
def gravatar_url(size: 128)
  hash = Digest::SHA256.hexdigest(email_address.strip.downcase)
  "https://www.gravatar.com/avatar/#{hash}?s=#{size}&d=404"
end

def available_avatar_sources
  sources = ["initials"]
  sources << "gravatar" if has_gravatar?
  sources << "upload" if avatar.attached?
  sources
end
```

**Callbacks:**

```ruby
after_create_commit :check_gravatar_later
after_update_commit :check_gravatar_later, if: :saved_change_to_email_address?
```

### Authentication Model Changes

Add `avatar_url` column (string, nullable). Populated during OAuth callback with `auth_hash.info.image`. No UI exposure — data capture only for future use.

### GravatarService (`app/services/gravatar_service.rb`)

Checks if an email has a Gravatar via HTTP HEAD request.

```ruby
class GravatarService
  def self.check(email)
    hash = Digest::SHA256.hexdigest(email.strip.downcase)
    uri = URI("https://www.gravatar.com/avatar/#{hash}?d=404")
    response = Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 5, read_timeout: 5) do |http|
      http.head(uri.request_uri)
    end
    response.code == "200"
  rescue StandardError
    false  # Network error — assume no Gravatar rather than blocking
  end
end
```

### CheckGravatarJob (`app/jobs/check_gravatar_job.rb`)

Background job that checks Gravatar and updates the user:

```ruby
class CheckGravatarJob < ApplicationJob
  queue_as :default

  def perform(user)
    has_gravatar = GravatarService.check(user.email_address)
    user.update_columns(has_gravatar: has_gravatar)
    # Note: does NOT auto-switch avatar_source to "gravatar".
    # The user discovers Gravatar is available via the source selection UI
    # and opts in explicitly. Respects user's current choice.
  end
end
```

### Avatar Display Helper (`app/helpers/avatar_helper.rb`)

Replaces inline avatar rendering throughout the app.

```ruby
def avatar_for(user, size: :md, aria_label: nil)
  # Single source of rendering logic for all avatar display.
  # Checks user.avatar_source to determine what to render:
  #   "upload"   → image_tag with Active Storage variant (resize_to_fill)
  #   "gravatar" → image_tag with user.gravatar_url(size: pixel_size)
  #   "initials" → colored circle div with user.initials text
  #
  # When aria_label is nil: renders aria-hidden="true" (decorative, name provides context)
  # When aria_label is provided: renders role="img" + aria-label (standalone avatar)
end
```

**Sizes:**

| Size | Pixels | Tailwind | Use case |
| ---- | ------ | -------- | -------- |
| `:xs` | 24px | `w-6 h-6` | Inline text, compact lists |
| `:sm` | 32px | `w-8 h-8` | Member lists, comments |
| `:md` | 40px | `w-10 h-10` | User menu trigger, cards |
| `:lg` | 64px | `w-16 h-16` | Profile header |
| `:xl` | 128px | `w-32 h-32` | Avatar editor preview |

**Renders:**

- **Upload source:** `image_tag` with Active Storage variant (`resize_to_fill: [size_px, size_px]`), `object-cover`, rounded
- **Gravatar source:** `image_tag` with Gravatar URL at the appropriate size, rounded
- **Initials source:** Colored circle with initials text, using `bg-interactive` and `text-text-on-interactive`

All outputs include: `rounded-full`, `object-cover` (for images), `aria-hidden="true"` (decorative — the user's name provides the accessible label in context).

### Profile Page Avatar Section

Added above the profile form on `account/profiles/edit.html.erb`:

```erb
<div class="flex items-center gap-6 mb-8" data-controller="modal">
  <%= avatar_for(@user, size: :xl) %>
  <div>
    <h2 class="text-lg font-semibold text-text-heading"><%= @user.full_name %></h2>
    <button data-action="click->modal#open"
            class="text-sm text-interactive underline hover:no-underline mt-1">
      <%= t("account.avatars.edit.change") %>
    </button>
  </div>

  <%= render "shared/image_upload_modal",
        title: t("account.avatars.edit.title"),
        form_url: account_avatar_path,
        field_name: :avatar,
        current_image: @user.avatar.attached? ? @user.avatar : nil,
        placeholder: avatar_for(@user, size: :xl),
        remove_url: @user.avatar.attached? ? account_avatar_path : nil,
        crop: true, aspect_ratio: 1, max_width: 512, max_height: 512 %>
</div>

<%# Source selection (when multiple sources available) %>
<% if @user.available_avatar_sources.size > 1 %>
  <%= form_with url: account_avatar_path, method: :patch, class: "mb-8" do |f| %>
    <fieldset class="space-y-2">
      <legend class="text-sm font-medium text-text-body"><%= t("account.avatars.source_label") %></legend>
      <% @user.available_avatar_sources.each do |source| %>
        <label class="flex items-center gap-3 min-h-[44px]">
          <%= f.radio_button :avatar_source, source,
                checked: @user.avatar_source == source,
                class: "size-5 text-interactive focus:ring-2 focus:ring-interactive-focus",
                data: { action: "change->form#requestSubmit" } %>
          <span class="text-sm text-text-body"><%= t("account.avatars.sources.#{source}") %></span>
        </label>
      <% end %>
    </fieldset>
  <% end %>
<% end %>
```

### User Model Validation

Active Storage attachment validation (server-side security boundary):

```ruby
validates :avatar,
  content_type: %w[image/png image/jpeg image/gif image/webp],
  size: { less_than: 5.megabytes }
```

### Avatars Controller Updates

The existing `account/avatars_controller.rb` needs:

- `authorize Current.user` in each action (Pundit — project requirement)
- `update` action handles both file upload AND `avatar_source` changes
- On file upload: set `avatar_source` to `"upload"` automatically
- On source change (no file): just update `avatar_source`
- Respond with redirect (Turbo handles the page update) and success toast
- `format.html` fallback for non-Turbo requests

### OmniAuth Callback Update

In `omniauth_callbacks_controller.rb`, save the avatar URL when creating/updating an authentication:

```ruby
authentication.update(avatar_url: auth_hash.info.image) if auth_hash.info.image.present?
```

### User Menu Update

Replace inline avatar rendering in `_user_menu.html.erb` with:

```erb
<%= avatar_for(Current.user, size: :md) %>
```

## I18n Keys

```yaml
en:
  account:
    avatars:
      edit:
        title: "Change avatar"
        change: "Change avatar"
      update:
        success: "Avatar updated."
      destroy:
        success: "Avatar removed."
      source_label: "Avatar source"
      source_updated: "Avatar source updated."
      sources:
        upload: "Uploaded photo"
        gravatar: "Gravatar"
        initials: "Initials"
```

## Accessibility

- **Avatar display:** Decorative by default (`aria-hidden="true"`) when the user's name provides context. For standalone use (no adjacent name), pass `aria_label: user.full_name` to `avatar_for` which renders `role="img"` + `aria-label` instead.
- **Source selection:** Uses `<fieldset>` with `<legend>` (I18n key) for screen reader grouping. Radio buttons meet 44px touch targets. Auto-submit on change uses Stimulus action (not inline JS).
- **Initials rendering:** Initials circle uses `aria-hidden="true"` — it's a visual representation of the user's name, not additional information.
- **Gravatar images:** Include `alt=""` (decorative) when name is adjacent, or `alt` with user name when standalone.
- **Image upload modal:** Inherits all modal accessibility (focus trap, Escape key, ARIA, touch targets, reduced motion).
- **Gravatar check:** Async via background job — no blocking on page load, no user-facing delay.
- **All UI text uses I18n keys** — no hardcoded strings in views or helpers.

## Files

| File | Action | Purpose |
| ---- | ------ | ------- |
| `db/migrate/*_add_avatar_fields.rb` | Create | Add avatar_source, has_gravatar to users; avatar_url to authentications |
| `app/models/user.rb` | Modify | Avatar source methods, Gravatar URL, callbacks |
| `app/services/gravatar_service.rb` | Create | HTTP HEAD check for Gravatar |
| `app/jobs/check_gravatar_job.rb` | Create | Async Gravatar check |
| `app/helpers/avatar_helper.rb` | Create | `avatar_for` display helper |
| `app/controllers/account/avatars_controller.rb` | Modify | Handle source changes, Turbo Stream response |
| `app/controllers/omniauth_callbacks_controller.rb` | Modify | Save OAuth avatar URL |
| `app/views/account/profiles/edit.html.erb` | Modify | Add avatar section with modal |
| `app/views/shared/_user_menu.html.erb` | Modify | Use avatar_for helper |
| `config/locales/en/account.en.yml` | Modify | Add avatar I18n keys |
| `spec/models/user_spec.rb` | Modify | Avatar source, Gravatar URL specs |
| `spec/services/gravatar_service_spec.rb` | Create | Service specs |
| `spec/jobs/check_gravatar_job_spec.rb` | Create | Job specs |
| `spec/helpers/avatar_helper_spec.rb` | Create | Helper specs |
| `spec/requests/account/avatars_spec.rb` | Modify | Source change, upload specs |
| `spec/system/avatar_spec.rb` | Create | End-to-end avatar editing |

## Testing Strategy

**Unit specs:**
- `GravatarService.check` returns true for valid Gravatar, false for missing, false on network error
- `CheckGravatarJob` updates `has_gravatar` (does not change `avatar_source`)
- `User#gravatar_url` generates correct SHA256-based URL
- `User#available_avatar_sources` returns correct list based on state
- `User` validates `avatar_source` inclusion
- `User` validates avatar content type and size (Active Storage validations)
- `avatar_for` helper renders image for upload source, Gravatar URL for gravatar source, initials for initials source
- `avatar_for` helper renders `aria-hidden` by default, `role="img"` + `aria-label` when label provided

**Request specs:**
- Upload avatar sets source to "upload"
- Upload rejects invalid content type (returns 422)
- Upload rejects oversized file (returns 422)
- Change source via radio buttons updates user
- Remove avatar falls back to initials source
- Unauthenticated access redirected
- Pundit authorization enforced

**System specs:**
- Open avatar modal from profile page
- Upload image via modal
- Select Gravatar source (when available)
- Select initials source
- Avatar updates in header after change

## Out of Scope

- OAuth avatar as selectable source (data captured but not surfaced)
- Custom initials color picker
- Image rotation/flip in cropper
- Avatar group component (stacked avatars in member lists)
- Banner/background image uploads (future consumer of image upload modal)
