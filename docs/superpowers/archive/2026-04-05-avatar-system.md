# Avatar System Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build an avatar system with Gravatar integration, source selection (upload/gravatar/initials), and a reusable avatar_for display helper.

**Architecture:** The User model gains `avatar_source` (enum: upload/gravatar/initials) and `has_gravatar` (boolean) columns. A `GravatarService` performs SHA256-based HTTP HEAD checks, run asynchronously via `CheckGravatarJob`. A single `avatar_for(user, size:)` helper in `AvatarHelper` is the sole rendering entry point for avatars across the entire app, replacing all inline avatar markup.

**Tech Stack:** Rails 8.1, Active Storage, ActiveJob (Solid Queue), RSpec

**Spec:** `docs/superpowers/specs/2026-04-05-avatar-system-design.md`

**Prerequisite:** Image Upload Modal must be implemented first.

---

## File Structure

| File | Action | Responsibility |
| ---- | ------ | -------------- |
| `db/migrate/*_add_avatar_fields_to_users_and_authentications.rb` | Create | Add avatar_source, has_gravatar to users; avatar_url to authentications |
| `app/services/gravatar_service.rb` | Create | HTTP HEAD check for Gravatar existence |
| `app/jobs/check_gravatar_job.rb` | Create | Async Gravatar check, updates has_gravatar |
| `app/models/user.rb` | Modify | Avatar source validation, gravatar_url, available_avatar_sources, callbacks, Active Storage validation |
| `app/helpers/avatar_helper.rb` | Create | `avatar_for` display helper |
| `config/locales/en/account.en.yml` | Modify | Add avatar I18n keys |
| `app/controllers/account/avatars_controller.rb` | Modify | Handle source changes, Pundit authorization, file upload + source update |
| `app/views/shared/_user_menu.html.erb` | Modify | Replace inline avatar with `avatar_for` |
| `app/views/account/profiles/edit.html.erb` | Modify | Add avatar section with modal and source selection |
| `app/controllers/omniauth_callbacks_controller.rb` | Modify | Save OAuth avatar URL to authentication |
| `spec/services/gravatar_service_spec.rb` | Create | Service specs |
| `spec/jobs/check_gravatar_job_spec.rb` | Create | Job specs |
| `spec/models/user_spec.rb` | Modify | Avatar source, gravatar_url, available_avatar_sources, validation specs |
| `spec/helpers/avatar_helper_spec.rb` | Create | Helper rendering specs |
| `spec/requests/account/avatars_spec.rb` | Modify | Source change, upload, authorization specs |
| `spec/system/avatar_spec.rb` | Create | End-to-end avatar editing |

---

### Task 1: Database Migration

**Files:**

- Create: `db/migrate/YYYYMMDDHHMMSS_add_avatar_fields_to_users_and_authentications.rb`

- [ ] **Step 1: Generate migration**

```bash
bin/rails generate migration AddAvatarFieldsToUsersAndAuthentications
```

- [ ] **Step 2: Write migration**

Edit the generated migration file:

```ruby
class AddAvatarFieldsToUsersAndAuthentications < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :avatar_source, :string, default: "initials", null: false
    add_column :users, :has_gravatar, :boolean, default: false, null: false
    add_column :authentications, :avatar_url, :string
  end
end
```

- [ ] **Step 3: Run migration**

```bash
bin/rails db:migrate
```

- [ ] **Step 4: Commit**

```bash
git add db/migrate/*_add_avatar_fields_to_users_and_authentications.rb db/schema.rb
git commit -m "feat: add avatar_source and has_gravatar to users, avatar_url to authentications"
```

---

### Task 2: GravatarService (TDD)

**Files:**

- Create: `spec/services/gravatar_service_spec.rb`
- Create: `app/services/gravatar_service.rb`

- [ ] **Step 1: Write specs**

Create `spec/services/gravatar_service_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe GravatarService do
  describe ".check" do
    let(:email) { "user@example.com" }
    let(:hash) { Digest::SHA256.hexdigest(email.strip.downcase) }
    let(:gravatar_uri) { "https://www.gravatar.com/avatar/#{hash}?d=404" }

    it "returns true when Gravatar exists" do
      stub_request(:head, gravatar_uri).to_return(status: 200)
      expect(described_class.check(email)).to be true
    end

    it "returns false when Gravatar does not exist" do
      stub_request(:head, gravatar_uri).to_return(status: 404)
      expect(described_class.check(email)).to be false
    end

    it "returns false on network error" do
      stub_request(:head, gravatar_uri).to_timeout
      expect(described_class.check(email)).to be false
    end

    it "normalizes email before hashing" do
      normalized_hash = Digest::SHA256.hexdigest("user@example.com")
      stub_request(:head, "https://www.gravatar.com/avatar/#{normalized_hash}?d=404")
        .to_return(status: 200)
      expect(described_class.check("  User@Example.COM  ")).to be true
    end
  end
end
```

- [ ] **Step 2: Run specs (expect red)**

```bash
bundle exec rspec spec/services/gravatar_service_spec.rb
```

- [ ] **Step 3: Implement GravatarService**

Create `app/services/gravatar_service.rb`:

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
    false
  end
end
```

- [ ] **Step 4: Run specs (expect green)**

```bash
bundle exec rspec spec/services/gravatar_service_spec.rb
```

- [ ] **Step 5: Commit**

```bash
git add app/services/gravatar_service.rb spec/services/gravatar_service_spec.rb
git commit -m "feat: add GravatarService with SHA256 HTTP HEAD check"
```

---

### Task 3: CheckGravatarJob (TDD)

**Files:**

- Create: `spec/jobs/check_gravatar_job_spec.rb`
- Create: `app/jobs/check_gravatar_job.rb`

- [ ] **Step 1: Write specs**

Create `spec/jobs/check_gravatar_job_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe CheckGravatarJob, type: :job do
  let(:user) { create(:user) }

  it "updates has_gravatar to true when Gravatar exists" do
    allow(GravatarService).to receive(:check).with(user.email_address).and_return(true)
    described_class.perform_now(user)
    expect(user.reload.has_gravatar).to be true
  end

  it "updates has_gravatar to false when Gravatar does not exist" do
    user.update_columns(has_gravatar: true)
    allow(GravatarService).to receive(:check).with(user.email_address).and_return(false)
    described_class.perform_now(user)
    expect(user.reload.has_gravatar).to be false
  end

  it "does NOT change avatar_source" do
    user.update_columns(avatar_source: "initials")
    allow(GravatarService).to receive(:check).with(user.email_address).and_return(true)
    described_class.perform_now(user)
    expect(user.reload.avatar_source).to eq("initials")
  end
end
```

- [ ] **Step 2: Run specs (expect red)**

```bash
bundle exec rspec spec/jobs/check_gravatar_job_spec.rb
```

- [ ] **Step 3: Implement CheckGravatarJob**

Create `app/jobs/check_gravatar_job.rb`:

```ruby
class CheckGravatarJob < ApplicationJob
  queue_as :default

  def perform(user)
    has_gravatar = GravatarService.check(user.email_address)
    user.update_columns(has_gravatar: has_gravatar)
  end
end
```

- [ ] **Step 4: Run specs (expect green)**

```bash
bundle exec rspec spec/jobs/check_gravatar_job_spec.rb
```

- [ ] **Step 5: Commit**

```bash
git add app/jobs/check_gravatar_job.rb spec/jobs/check_gravatar_job_spec.rb
git commit -m "feat: add CheckGravatarJob to async check Gravatar availability"
```

---

### Task 4: User Model Avatar Methods (TDD)

**Files:**

- Modify: `spec/models/user_spec.rb`
- Modify: `app/models/user.rb`

- [ ] **Step 1: Add specs to `spec/models/user_spec.rb`**

Add the following describe blocks to the existing user spec file:

```ruby
describe "avatar_source validation" do
  it "allows 'upload' as avatar_source" do
    user = build(:user, avatar_source: "upload")
    user.valid?
    expect(user.errors[:avatar_source]).to be_empty
  end

  it "allows 'gravatar' as avatar_source" do
    user = build(:user, avatar_source: "gravatar")
    user.valid?
    expect(user.errors[:avatar_source]).to be_empty
  end

  it "allows 'initials' as avatar_source" do
    user = build(:user, avatar_source: "initials")
    user.valid?
    expect(user.errors[:avatar_source]).to be_empty
  end

  it "rejects invalid avatar_source" do
    user = build(:user, avatar_source: "invalid")
    expect(user).not_to be_valid
    expect(user.errors[:avatar_source]).to be_present
  end
end

describe "#gravatar_url" do
  it "generates a SHA256-based Gravatar URL" do
    user = build(:user, email_address: "test@example.com")
    hash = Digest::SHA256.hexdigest("test@example.com")
    expect(user.gravatar_url).to eq("https://www.gravatar.com/avatar/#{hash}?s=128&d=404")
  end

  it "accepts a custom size" do
    user = build(:user, email_address: "test@example.com")
    expect(user.gravatar_url(size: 64)).to include("s=64")
  end

  it "normalizes email before hashing" do
    user = build(:user, email_address: "Test@Example.COM")
    hash = Digest::SHA256.hexdigest("test@example.com")
    expect(user.gravatar_url).to include(hash)
  end
end

describe "#available_avatar_sources" do
  it "always includes initials" do
    user = build(:user)
    expect(user.available_avatar_sources).to include("initials")
  end

  it "includes gravatar when has_gravatar is true" do
    user = build(:user, has_gravatar: true)
    expect(user.available_avatar_sources).to include("gravatar")
  end

  it "excludes gravatar when has_gravatar is false" do
    user = build(:user, has_gravatar: false)
    expect(user.available_avatar_sources).not_to include("gravatar")
  end

  it "includes upload when avatar is attached" do
    user = create(:user)
    user.avatar.attach(io: File.open(Rails.root.join("spec/fixtures/files/avatar.png")), filename: "avatar.png", content_type: "image/png")
    expect(user.available_avatar_sources).to include("upload")
  end

  it "excludes upload when avatar is not attached" do
    user = build(:user)
    expect(user.available_avatar_sources).not_to include("upload")
  end
end

describe "avatar Active Storage validations" do
  it "accepts valid image content types" do
    user = create(:user)
    %w[image/png image/jpeg image/gif image/webp].each do |content_type|
      user.avatar.attach(io: StringIO.new("fake"), filename: "test.png", content_type: content_type)
      user.valid?
      expect(user.errors[:avatar]).to be_empty, "Expected #{content_type} to be valid"
    end
  end

  it "rejects invalid content types" do
    user = create(:user)
    user.avatar.attach(io: StringIO.new("fake"), filename: "test.txt", content_type: "text/plain")
    expect(user).not_to be_valid
    expect(user.errors[:avatar]).to be_present
  end

  it "rejects files over 5MB" do
    user = create(:user)
    large_io = StringIO.new("x" * 6.megabytes)
    user.avatar.attach(io: large_io, filename: "big.png", content_type: "image/png")
    expect(user).not_to be_valid
    expect(user.errors[:avatar]).to be_present
  end
end

describe "Gravatar check callbacks" do
  it "enqueues CheckGravatarJob after create" do
    expect {
      create(:user)
    }.to have_enqueued_job(CheckGravatarJob)
  end

  it "enqueues CheckGravatarJob after email change" do
    user = create(:user)
    expect {
      user.update!(email_address: "newemail@example.com")
    }.to have_enqueued_job(CheckGravatarJob)
  end

  it "does not enqueue CheckGravatarJob when email does not change" do
    user = create(:user)
    expect {
      user.update!(first_name: "Updated")
    }.not_to have_enqueued_job(CheckGravatarJob)
  end
end
```

- [ ] **Step 2: Run specs (expect red)**

```bash
bundle exec rspec spec/models/user_spec.rb
```

- [ ] **Step 3: Implement User model changes**

Add the following to `app/models/user.rb`. Add the validation after the existing `validates :pending_email` line:

```ruby
validates :avatar_source, inclusion: { in: %w[upload gravatar initials] }
validates :avatar,
  content_type: %w[image/png image/jpeg image/gif image/webp],
  size: { less_than: 5.megabytes }
```

Add the callbacks after the existing `after_create :create_personal_workspace` line:

```ruby
after_create_commit :check_gravatar_later
after_update_commit :check_gravatar_later, if: :saved_change_to_email_address?
```

Add the public methods after the existing `has_password?` method:

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

Add the private method inside the `private` section:

```ruby
def check_gravatar_later
  CheckGravatarJob.perform_later(self)
end
```

- [ ] **Step 4: Run specs (expect green)**

```bash
bundle exec rspec spec/models/user_spec.rb
```

- [ ] **Step 5: Commit**

```bash
git add app/models/user.rb spec/models/user_spec.rb
git commit -m "feat: add avatar source validation, gravatar_url, and Gravatar check callbacks to User"
```

---

### Task 5: Avatar Display Helper (TDD)

**Files:**

- Create: `spec/helpers/avatar_helper_spec.rb`
- Create: `app/helpers/avatar_helper.rb`

- [ ] **Step 1: Write specs**

Create `spec/helpers/avatar_helper_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe AvatarHelper, type: :helper do
  let(:user) { create(:user, first_name: "Jane", last_name: "Doe") }

  describe "#avatar_for" do
    context "with upload source" do
      before do
        user.avatar.attach(
          io: File.open(Rails.root.join("spec/fixtures/files/avatar.png")),
          filename: "avatar.png",
          content_type: "image/png"
        )
        user.update_columns(avatar_source: "upload")
      end

      it "renders an image tag with Active Storage variant" do
        result = helper.avatar_for(user, size: :md)
        expect(result).to have_css("img.rounded-full.object-cover")
      end

      it "renders correct size classes" do
        result = helper.avatar_for(user, size: :lg)
        expect(result).to have_css("img.w-16.h-16")
      end

      it "renders aria-hidden by default" do
        result = helper.avatar_for(user, size: :md)
        expect(result).to have_css("img[aria-hidden='true']")
      end

      it "renders role=img with aria_label when provided" do
        result = helper.avatar_for(user, size: :md, aria_label: "Jane Doe")
        expect(result).to have_css("img[role='img'][aria-label='Jane Doe']")
        expect(result).not_to have_css("img[aria-hidden]")
      end
    end

    context "with gravatar source" do
      before do
        user.update_columns(avatar_source: "gravatar", has_gravatar: true)
      end

      it "renders an image tag with Gravatar URL" do
        result = helper.avatar_for(user, size: :md)
        hash = Digest::SHA256.hexdigest(user.email_address.strip.downcase)
        expect(result).to have_css("img[src*='gravatar.com/avatar/#{hash}']")
      end

      it "passes correct pixel size to Gravatar URL" do
        result = helper.avatar_for(user, size: :lg)
        expect(result).to have_css("img[src*='s=64']")
      end

      it "renders aria-hidden by default" do
        result = helper.avatar_for(user, size: :md)
        expect(result).to have_css("img[aria-hidden='true']")
      end
    end

    context "with initials source" do
      before do
        user.update_columns(avatar_source: "initials")
      end

      it "renders a span with initials text" do
        result = helper.avatar_for(user, size: :md)
        expect(result).to have_css("span", text: "JD")
      end

      it "renders correct Tailwind classes" do
        result = helper.avatar_for(user, size: :md)
        expect(result).to have_css("span.rounded-full.bg-interactive.text-text-on-interactive")
      end

      it "renders correct size classes" do
        result = helper.avatar_for(user, size: :sm)
        expect(result).to have_css("span.w-8.h-8")
      end

      it "renders aria-hidden by default" do
        result = helper.avatar_for(user, size: :md)
        expect(result).to have_css("span[aria-hidden='true']")
      end

      it "renders role=img with aria_label when provided" do
        result = helper.avatar_for(user, size: :md, aria_label: "Jane Doe")
        expect(result).to have_css("span[role='img'][aria-label='Jane Doe']")
      end
    end

    context "sizes" do
      before { user.update_columns(avatar_source: "initials") }

      it "renders xs size" do
        result = helper.avatar_for(user, size: :xs)
        expect(result).to have_css("span.w-6.h-6")
      end

      it "renders sm size" do
        result = helper.avatar_for(user, size: :sm)
        expect(result).to have_css("span.w-8.h-8")
      end

      it "renders md size" do
        result = helper.avatar_for(user, size: :md)
        expect(result).to have_css("span.w-10.h-10")
      end

      it "renders lg size" do
        result = helper.avatar_for(user, size: :lg)
        expect(result).to have_css("span.w-16.h-16")
      end

      it "renders xl size" do
        result = helper.avatar_for(user, size: :xl)
        expect(result).to have_css("span.w-32.h-32")
      end
    end
  end
end
```

- [ ] **Step 2: Run specs (expect red)**

```bash
bundle exec rspec spec/helpers/avatar_helper_spec.rb
```

- [ ] **Step 3: Implement AvatarHelper**

Create `app/helpers/avatar_helper.rb`:

```ruby
module AvatarHelper
  AVATAR_SIZES = {
    xs: { css: "w-6 h-6", px: 24, text: "text-xs" },
    sm: { css: "w-8 h-8", px: 32, text: "text-xs" },
    md: { css: "w-10 h-10", px: 40, text: "text-sm" },
    lg: { css: "w-16 h-16", px: 64, text: "text-lg" },
    xl: { css: "w-32 h-32", px: 128, text: "text-3xl" }
  }.freeze

  def avatar_for(user, size: :md, aria_label: nil)
    config = AVATAR_SIZES.fetch(size)

    case user.avatar_source
    when "upload"
      render_upload_avatar(user, config, aria_label)
    when "gravatar"
      render_gravatar_avatar(user, config, aria_label)
    else
      render_initials_avatar(user, config, aria_label)
    end
  end

  private

  def render_upload_avatar(user, config, aria_label)
    variant = user.avatar.variant(resize_to_fill: [config[:px], config[:px]])
    image_tag variant,
      class: "#{config[:css]} rounded-full object-cover",
      **avatar_aria_attrs(aria_label, alt: "")
  end

  def render_gravatar_avatar(user, config, aria_label)
    image_tag user.gravatar_url(size: config[:px]),
      class: "#{config[:css]} rounded-full object-cover",
      **avatar_aria_attrs(aria_label, alt: "")
  end

  def render_initials_avatar(user, config, aria_label)
    content_tag :span, user.initials,
      class: "#{config[:css]} #{config[:text]} rounded-full bg-interactive text-text-on-interactive
              flex items-center justify-center font-semibold",
      **avatar_aria_attrs(aria_label)
  end

  def avatar_aria_attrs(aria_label, alt: nil)
    if aria_label
      attrs = { role: "img", aria: { label: aria_label } }
      attrs[:alt] = aria_label if alt == ""
      attrs
    else
      attrs = { aria: { hidden: true } }
      attrs[:alt] = "" if alt == ""
      attrs
    end
  end
end
```

- [ ] **Step 4: Run specs (expect green)**

```bash
bundle exec rspec spec/helpers/avatar_helper_spec.rb
```

- [ ] **Step 5: Commit**

```bash
git add app/helpers/avatar_helper.rb spec/helpers/avatar_helper_spec.rb
git commit -m "feat: add avatar_for display helper with upload, gravatar, and initials rendering"
```

---

### Task 6: Update I18n Keys

**Files:**

- Modify: `config/locales/en/account.en.yml`

- [ ] **Step 1: Update I18n keys**

Replace the existing `avatars` section in `config/locales/en/account.en.yml` with:

```yaml
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

This replaces the existing keys (`update.success`, `update.no_file`, `destroy.removed`) with the new key structure. Update any references in specs or controllers that use the old keys.

- [ ] **Step 2: Commit**

```bash
git add config/locales/en/account.en.yml
git commit -m "feat: update avatar I18n keys with source selection labels"
```

---

### Task 7: Update Avatars Controller (TDD)

**Files:**

- Modify: `spec/requests/account/avatars_spec.rb`
- Modify: `app/controllers/account/avatars_controller.rb`

- [ ] **Step 1: Rewrite specs**

Replace the contents of `spec/requests/account/avatars_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe "Account Avatars", type: :request do
  describe "unauthenticated access" do
    it "redirects PATCH /account/avatar to sign in" do
      patch account_avatar_path
      expect(response).to redirect_to(new_session_path)
    end

    it "redirects DELETE /account/avatar to sign in" do
      delete account_avatar_path
      expect(response).to redirect_to(new_session_path)
    end
  end

  context "authenticated" do
    let(:user) { create(:user) }
    before { sign_in(user) }

    describe "PATCH /account/avatar" do
      it "uploads an avatar and sets source to upload" do
        file = fixture_file_upload("avatar.png", "image/png")
        patch account_avatar_path, params: { user: { avatar: file } }
        user.reload
        expect(user.avatar).to be_attached
        expect(user.avatar_source).to eq("upload")
        expect(response).to redirect_to(edit_account_profile_path)
      end

      it "rejects invalid content type" do
        file = fixture_file_upload("document.txt", "text/plain")
        patch account_avatar_path, params: { user: { avatar: file } }
        expect(response).to have_http_status(:unprocessable_entity)
      end

      it "rejects oversized file" do
        file = fixture_file_upload("oversized.png", "image/png")
        patch account_avatar_path, params: { user: { avatar: file } }
        expect(response).to have_http_status(:unprocessable_entity)
      end

      it "changes avatar source without uploading a file" do
        user.update_columns(has_gravatar: true)
        patch account_avatar_path, params: { user: { avatar_source: "gravatar" } }
        expect(user.reload.avatar_source).to eq("gravatar")
        expect(response).to redirect_to(edit_account_profile_path)
      end

      it "rejects invalid avatar source" do
        patch account_avatar_path, params: { user: { avatar_source: "invalid" } }
        expect(response).to have_http_status(:unprocessable_entity)
      end
    end

    describe "DELETE /account/avatar" do
      it "removes the avatar and falls back to initials" do
        user.avatar.attach(
          io: File.open(Rails.root.join("spec/fixtures/files/avatar.png")),
          filename: "avatar.png",
          content_type: "image/png"
        )
        user.update_columns(avatar_source: "upload")
        delete account_avatar_path
        user.reload
        expect(user.avatar).not_to be_attached
        expect(user.avatar_source).to eq("initials")
        expect(response).to redirect_to(edit_account_profile_path)
      end
    end
  end
end
```

Note: The specs referencing `document.txt` and `oversized.png` require test fixture files. Create `spec/fixtures/files/document.txt` with any text content. Create `spec/fixtures/files/oversized.png` as a file larger than 5MB (use a script or a stub in the spec setup to generate it). If generating a real file is impractical, use `Rack::Test::UploadedFile` with a `StringIO` in the spec instead of `fixture_file_upload`.

- [ ] **Step 2: Run specs (expect red)**

```bash
bundle exec rspec spec/requests/account/avatars_spec.rb
```

- [ ] **Step 3: Update controller**

Replace `app/controllers/account/avatars_controller.rb`:

```ruby
module Account
  class AvatarsController < ApplicationController
    def update
      authorize Current.user

      file = params.dig(:user, :avatar)

      if file.present?
        Current.user.avatar.attach(file)
        Current.user.avatar_source = "upload"

        if Current.user.save
          redirect_to edit_account_profile_path, notice: t(".success")
        else
          Current.user.avatar.purge
          render :edit, status: :unprocessable_entity
        end
      elsif params.dig(:user, :avatar_source).present?
        if Current.user.update(avatar_source: params[:user][:avatar_source])
          redirect_to edit_account_profile_path, notice: t("account.avatars.source_updated")
        else
          render :edit, status: :unprocessable_entity
        end
      else
        redirect_to edit_account_profile_path
      end
    end

    def destroy
      authorize Current.user

      Current.user.avatar.purge
      Current.user.update!(avatar_source: "initials")
      redirect_to edit_account_profile_path, notice: t(".success")
    end
  end
end
```

- [ ] **Step 4: Create test fixture files**

Create `spec/fixtures/files/document.txt`:

```
This is a test document.
```

Create a script or helper to generate `spec/fixtures/files/oversized.png` for the oversized file test. Alternatively, modify the oversized spec to use an inline `Rack::Test::UploadedFile` with a `StringIO`:

```ruby
it "rejects oversized file" do
  large_io = Rack::Test::UploadedFile.new(
    StringIO.new("x" * 6.megabytes), "image/png", original_filename: "oversized.png"
  )
  patch account_avatar_path, params: { user: { avatar: large_io } }
  expect(response).to have_http_status(:unprocessable_entity)
end
```

- [ ] **Step 5: Run specs (expect green)**

```bash
bundle exec rspec spec/requests/account/avatars_spec.rb
```

- [ ] **Step 6: Commit**

```bash
git add app/controllers/account/avatars_controller.rb spec/requests/account/avatars_spec.rb spec/fixtures/files/document.txt
git commit -m "feat: update avatars controller with source selection, Pundit auth, and validation"
```

---

### Task 8: Update User Menu to Use avatar_for

**Files:**

- Modify: `app/views/shared/_user_menu.html.erb`

- [ ] **Step 1: Replace inline avatar rendering**

In `app/views/shared/_user_menu.html.erb`, replace the inline avatar block (lines 15-23):

```erb
      <% if Current.user.avatar.attached? %>
        <%= image_tag Current.user.avatar, class: "w-10 h-10 rounded-full object-cover", alt: "" %>
      <% else %>
        <span class="w-10 h-10 rounded-full bg-interactive text-text-on-interactive
                     flex items-center justify-center text-sm font-semibold"
              aria-hidden="true">
          <%= Current.user.initials %>
        </span>
      <% end %>
```

With:

```erb
      <%= avatar_for(Current.user, size: :md) %>
```

- [ ] **Step 2: Commit**

```bash
git add app/views/shared/_user_menu.html.erb
git commit -m "refactor: replace inline avatar rendering with avatar_for helper in user menu"
```

---

### Task 9: Update Profile Page with Avatar Section

**Files:**

- Modify: `app/views/account/profiles/edit.html.erb`

- [ ] **Step 1: Add avatar section above profile form**

In `app/views/account/profiles/edit.html.erb`, add the avatar section after the `<h1>` tag (after line 5) and before the `form_with` block (line 7):

```erb
  <%# Avatar preview and editor %>
  <div class="flex items-center gap-6 mt-8 mb-8" data-controller="modal">
    <%= avatar_for(@user, size: :xl) %>
    <div>
      <h2 class="text-lg font-semibold text-text-heading"><%= @user.full_name %></h2>
      <button data-action="click->modal#open"
              type="button"
              class="text-sm text-interactive underline hover:no-underline mt-1
                     min-h-[44px] min-w-[44px]
                     focus:outline-none focus:ring-2 focus:ring-interactive-focus rounded">
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
        <legend class="text-sm font-medium text-text-body">
          <%= t("account.avatars.source_label") %>
        </legend>
        <% @user.available_avatar_sources.each do |source| %>
          <label class="flex items-center gap-3 min-h-[44px]">
            <%= f.radio_button :avatar_source, source,
                  checked: @user.avatar_source == source,
                  class: "size-5 text-interactive focus:ring-2 focus:ring-interactive-focus",
                  data: { action: "change->form#requestSubmit" } %>
            <span class="text-sm text-text-body">
              <%= t("account.avatars.sources.#{source}") %>
            </span>
          </label>
        <% end %>
      </fieldset>
    <% end %>
  <% end %>
```

Note: The `form_with` radio buttons are nested inside a `user` namespace automatically. The `data-action="change->form#requestSubmit"` triggers auto-submit via the Stimulus form controller when a radio button is selected.

- [ ] **Step 2: Commit**

```bash
git add app/views/account/profiles/edit.html.erb
git commit -m "feat: add avatar preview, upload modal, and source selection to profile page"
```

---

### Task 10: Capture OAuth Avatar URLs

**Files:**

- Modify: `app/controllers/omniauth_callbacks_controller.rb`

- [ ] **Step 1: Update oauth_attrs to include avatar_url**

In `app/controllers/omniauth_callbacks_controller.rb`, update the `oauth_attrs` private method to include the avatar URL:

Replace the existing `oauth_attrs` method:

```ruby
  def oauth_attrs(auth_hash)
    {
      oauth_token: auth_hash.credentials.token,
      oauth_refresh_token: auth_hash.credentials.refresh_token,
      oauth_expires_at: auth_hash.credentials.expires_at ? Time.at(auth_hash.credentials.expires_at) : nil
    }
  end
```

With:

```ruby
  def oauth_attrs(auth_hash)
    attrs = {
      oauth_token: auth_hash.credentials.token,
      oauth_refresh_token: auth_hash.credentials.refresh_token,
      oauth_expires_at: auth_hash.credentials.expires_at ? Time.at(auth_hash.credentials.expires_at) : nil
    }
    attrs[:avatar_url] = auth_hash.info.image if auth_hash.info.image.present?
    attrs
  end
```

- [ ] **Step 2: Commit**

```bash
git add app/controllers/omniauth_callbacks_controller.rb
git commit -m "feat: capture OAuth avatar URL on authentication records"
```

---

### Task 11: System Specs

**Files:**

- Create: `spec/system/avatar_spec.rb`

- [ ] **Step 1: Write system specs**

Create `spec/system/avatar_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe "Avatar management", type: :system do
  let(:user) { create(:user) }

  before do
    sign_in(user)
  end

  it "displays initials avatar in user menu by default" do
    visit root_path
    within("[data-controller='dropdown']") do
      expect(page).to have_css("span", text: user.initials)
    end
  end

  it "opens avatar modal from profile page" do
    visit edit_account_profile_path
    click_button t("account.avatars.edit.change")
    expect(page).to have_css("dialog[open]")
    expect(page).to have_text(t("account.avatars.edit.title"))
  end

  it "uploads an avatar image" do
    visit edit_account_profile_path
    click_button t("account.avatars.edit.change")

    within("dialog") do
      attach_file(t("account.avatars.edit.title"), Rails.root.join("spec/fixtures/files/avatar.png"), make_visible: true)
      click_button t("account.avatars.update.success").chomp(".")  # or submit button text
    end

    expect(page).to have_text(t("account.avatars.update.success"))
    expect(user.reload.avatar_source).to eq("upload")
  end

  it "shows source selection when multiple sources are available" do
    user.avatar.attach(
      io: File.open(Rails.root.join("spec/fixtures/files/avatar.png")),
      filename: "avatar.png",
      content_type: "image/png"
    )
    user.update_columns(avatar_source: "upload")

    visit edit_account_profile_path
    expect(page).to have_text(t("account.avatars.source_label"))
    expect(page).to have_field(type: "radio", count: user.available_avatar_sources.size)
  end

  it "switches avatar source to initials" do
    user.avatar.attach(
      io: File.open(Rails.root.join("spec/fixtures/files/avatar.png")),
      filename: "avatar.png",
      content_type: "image/png"
    )
    user.update_columns(avatar_source: "upload")

    visit edit_account_profile_path
    choose t("account.avatars.sources.initials")

    expect(page).to have_text(t("account.avatars.source_updated"))
    expect(user.reload.avatar_source).to eq("initials")
  end

  it "updates avatar in header after source change" do
    user.avatar.attach(
      io: File.open(Rails.root.join("spec/fixtures/files/avatar.png")),
      filename: "avatar.png",
      content_type: "image/png"
    )
    user.update_columns(avatar_source: "upload")

    visit edit_account_profile_path
    choose t("account.avatars.sources.initials")

    within("[data-controller='dropdown']") do
      expect(page).to have_css("span", text: user.initials)
    end
  end
end
```

Note: System specs may need adjustment based on the actual image upload modal implementation and submit button text. The `t()` helper calls reference I18n keys added in Task 6. Adapt selectors and flow to match the modal partial's actual markup.

- [ ] **Step 2: Commit**

```bash
git add spec/system/avatar_spec.rb
git commit -m "test: add system specs for avatar upload, source selection, and display"
```

---

### Task 12: Full Test Suite

- [ ] **Step 1: Run full test suite**

```bash
bundle exec rspec --order rand
```

- [ ] **Step 2: Verify all specs pass with 0 failures**

If any specs fail, fix the failures and re-run until the full suite is green. Do not proceed until all specs pass.

- [ ] **Step 3: Final commit (if any fixes were needed)**

```bash
git add -A
git commit -m "fix: resolve test failures from avatar system integration"
```
