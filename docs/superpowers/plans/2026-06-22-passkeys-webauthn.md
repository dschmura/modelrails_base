# Passkeys (WebAuthn) — Implementation Plan (Phase B)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add passkeys (WebAuthn) as the fast returning-login — an explicit usernameless "Sign in with a passkey" button plus conditional-UI autofill — backed by a dedicated credential model, a replay-safe DB challenge, and the existing magic-link as the universal fallback.

**Architecture:** Build on the core `webauthn` gem (cedarcode, `~> 3.0`). A dedicated `WebauthnCredential` model (register once, authenticate many) and a `WebauthnChallenge` DB nonce (atomic one-time consume, mirroring `MagicLinkToken`). Two thin PORO ceremonies (`Passkeys::RegisterCeremony`, `Passkeys::AuthenticateCeremony`) own orchestration; thin JSON controllers dispatch; a single `webauthn` Stimulus controller drives `navigator.credentials` (CSP-safe `fetch` + CSRF). All sign-ins converge on the existing `start_new_session_for`. Magic-link remains the floor (no last-credential guard).

**Tech Stack:** Rails 8.1, Ruby 4.0.4, `webauthn ~> 3.0`, RSpec + Capybara/Playwright (CDP virtual authenticator), Stimulus (importmap), TailwindCSS 4 / modelrails_ui (`UI::DialogComponent`/`UI::AlertDialogComponent`), SQLite.

## Global Constraints

- Ruby **4.0.4**, Rails **8.1**; run via `mise exec -- bundle exec …` and `mise exec -- bin/rails …`.
- **TDD, no exceptions:** failing test first, run red, implement, run green, commit.
- **Library:** core `webauthn` gem only; no Devise/Warden/SaaS. Verification is delegated entirely to the gem.
- **Namespacing:** our Ruby namespace is **`Passkeys::`** (ceremonies, errors) — never `Webauthn::`, to avoid colliding with the gem's `WebAuthn` constant. Models are top-level `WebauthnCredential` / `WebauthnChallenge`.
- **Security:** challenge is a DB nonce with **atomic one-time consume + expiry** (never the session); `sign_count` advanced **atomically** with clone detection; `external_id` and `users.webauthn_handle` **unique at the DB**; RP ID/origin pinned from config.
- **CSP:** no inline JS — the ceremony lives in a Stimulus controller using `fetch` + the `meta[name=csrf-token]` header (the `rating_controller.js` pattern).
- **A11y (WCAG 2.2 AAA, CI-proven):** passkey button label / 44px / `focus-ring` (never `focus:ring-*`) / focus-restore; `aria-live` for fetch outcomes; interstitial via `UI::DialogComponent`; settings remove via `UI::AlertDialogComponent` with per-item `aria-label`.
- **I18n:** all user-facing text via locale keys.
- **Recovery floor:** magic-link is always available → **no last-credential guard** on passkey removal.
- **Full RSpec suite green (0 failures)** before each commit; never bypass Lefthook; no Co-Authored-By / AI-attribution trailer.

---

## File Structure

**Create:**
- `config/initializers/webauthn.rb` — `WebAuthn.configure` (allowed_origins from host/env, rp_name from I18n) + `Passkeys.rp_id`/origin helpers.
- `db/migrate/*_create_webauthn_credentials.rb`, `*_create_webauthn_challenges.rb`, `*_add_webauthn_handle_to_users.rb`, `*_add_passkey_prompt_seen_at_to_users.rb`.
- `app/models/webauthn_credential.rb`, `app/models/webauthn_challenge.rb`.
- `app/lib/passkeys/errors.rb`, `app/lib/passkeys/register_ceremony.rb`, `app/lib/passkeys/authenticate_ceremony.rb`.
- `app/controllers/passkeys/registrations_controller.rb`, `app/controllers/passkeys/authentications_controller.rb`.
- `app/controllers/settings/passkeys_controller.rb` + `app/views/settings/passkeys/index.html.erb`.
- `app/javascript/controllers/webauthn_controller.js`.
- `app/views/shared/_passkey_enrollment_interstitial.html.erb`.
- `app/docs/passkeys.md`.
- `spec/support/webauthn_virtual_authenticator.rb`, `spec/factories/webauthn_credentials.rb`.
- specs per task.

**Modify:**
- `Gemfile` (+ `webauthn`), `config/routes.rb`, `app/models/user.rb`, `app/views/sessions/new.html.erb`, the authenticated layout (interstitial hook), `config/initializers/markdowndocs.rb` (index the doc), locale files.

---

### Task 1: Gem + WebAuthn configuration (RP ID / origin seam)

**Files:**
- Modify: `Gemfile`
- Create: `config/initializers/webauthn.rb`
- Test: `spec/initializers/webauthn_config_spec.rb`

**Interfaces — Produces:** `WebAuthn.configuration.allowed_origins`/`rp_name` configured; `Passkeys.rp_id` returns the configured RP id (the app host).

- [ ] **Step 1: Add the gem**

In `Gemfile` (near other auth gems): `gem "webauthn", "~> 3.0"`. Run `mise exec -- bundle install`.

- [ ] **Step 2: Failing test**

`spec/initializers/webauthn_config_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe "WebAuthn configuration" do
  it "pins allowed_origins to the app host so a misconfig fails loudly" do
    expect(WebAuthn.configuration.allowed_origins).to be_present
  end

  it "exposes the rp_id via Passkeys.rp_id" do
    expect(Passkeys.rp_id).to be_present
  end

  it "sets a relying-party name" do
    expect(WebAuthn.configuration.rp_name).to eq(I18n.t("application.name"))
  end
end
```

- [ ] **Step 3: Run red**

`mise exec -- bundle exec rspec spec/initializers/webauthn_config_spec.rb` → FAIL (no config / `Passkeys` undefined).

- [ ] **Step 4: Implement the initializer**

`config/initializers/webauthn.rb`:

```ruby
# Passkeys (WebAuthn) relying-party configuration.
#
# RP ID / origin MUST match window.location.origin in the browser. Derived from
# the app host (the same value mailers use), overridable per environment via
# WEBAUTHN_ORIGIN — the classic forker footgun, so it's a single explicit seam.
# See app/docs/passkeys.md.
module Passkeys
  def self.origin
    ENV.fetch("WEBAUTHN_ORIGIN") do
      host = Rails.application.config.action_mailer.default_url_options&.dig(:host) || "localhost:3000"
      scheme = host.start_with?("localhost", "127.0.0.1") ? "http" : "https"
      "#{scheme}://#{host}"
    end
  end

  def self.rp_id
    ENV.fetch("WEBAUTHN_RP_ID") { URI(origin).host }
  end
end

WebAuthn.configure do |config|
  config.allowed_origins = [ Passkeys.origin ]
  config.rp_name = I18n.t("application.name")
  config.rp_id = Passkeys.rp_id
end
```

- [ ] **Step 5: Green + commit**

`mise exec -- bundle exec rspec spec/initializers/webauthn_config_spec.rb` → PASS.

```bash
git add Gemfile Gemfile.lock config/initializers/webauthn.rb spec/initializers/webauthn_config_spec.rb
git commit -m "feat(passkeys): add webauthn gem + RP-id/origin config seam"
```

> Note: `webauthn` joins the Rails boot path — confirm any Rails-booting CI job still boots (the Gemfile-load-semantics lesson).

---

### Task 2: `WebauthnChallenge` model (replay-safe DB nonce)

**Files:**
- Migrate: `db/migrate/*_create_webauthn_challenges.rb`
- Create: `app/models/webauthn_challenge.rb`
- Test: `spec/models/webauthn_challenge_spec.rb`

**Interfaces — Produces:** `WebauthnChallenge.store(challenge:, purpose:, user: nil)` → record; `WebauthnChallenge.consume!(challenge, purpose:)` → record or `nil` (atomic, one-time, expiry-checked).

- [ ] **Step 1: Failing test**

`spec/models/webauthn_challenge_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe WebauthnChallenge do
  it "consumes a stored challenge exactly once" do
    WebauthnChallenge.store(challenge: "abc", purpose: "authentication")
    expect(WebauthnChallenge.consume!("abc", purpose: "authentication")).to be_present
    expect(WebauthnChallenge.consume!("abc", purpose: "authentication")).to be_nil # replay rejected
  end

  it "rejects an expired challenge" do
    WebauthnChallenge.store(challenge: "old", purpose: "authentication")
    WebauthnChallenge.find_by(challenge: "old").update_column(:expires_at, 1.minute.ago)
    expect(WebauthnChallenge.consume!("old", purpose: "authentication")).to be_nil
  end

  it "rejects a challenge consumed for the wrong purpose" do
    WebauthnChallenge.store(challenge: "reg", purpose: "registration")
    expect(WebauthnChallenge.consume!("reg", purpose: "authentication")).to be_nil
  end
end
```

- [ ] **Step 2: Run red** → `mise exec -- bundle exec rspec spec/models/webauthn_challenge_spec.rb` (no table/model).

- [ ] **Step 3: Migration**

`db/migrate/<ts>_create_webauthn_challenges.rb`:

```ruby
class CreateWebauthnChallenges < ActiveRecord::Migration[8.1]
  def change
    create_table :webauthn_challenges do |t|
      t.string :challenge, null: false
      t.string :purpose, null: false
      t.references :user, null: true, foreign_key: true
      t.datetime :expires_at, null: false
      t.datetime :consumed_at
      t.timestamps
    end
    add_index :webauthn_challenges, :challenge, unique: true
  end
end
```

Run `mise exec -- bin/rails db:migrate`.

- [ ] **Step 4: Model**

`app/models/webauthn_challenge.rb`:

```ruby
class WebauthnChallenge < ApplicationRecord
  belongs_to :user, optional: true
  validates :challenge, presence: true, uniqueness: true
  validates :purpose, inclusion: { in: %w[registration authentication] }

  def self.store(challenge:, purpose:, user: nil)
    create!(challenge: challenge, purpose: purpose, user: user, expires_at: 5.minutes.from_now)
  end

  # Atomic compare-and-swap (the MagicLinkToken pattern): one UPDATE guarded by
  # consumed_at IS NULL + expiry + purpose, so concurrent consumers are
  # serialized by the database and only one sees affected_rows == 1.
  def self.consume!(challenge, purpose:)
    rows = where(challenge: challenge, purpose: purpose, consumed_at: nil)
             .where("expires_at > ?", Time.current)
             .update_all(consumed_at: Time.current)
    return nil unless rows > 0
    find_by(challenge: challenge)
  end
end
```

- [ ] **Step 5: Green + commit**

```bash
mise exec -- bundle exec rspec spec/models/webauthn_challenge_spec.rb
git add db/migrate db/schema.rb app/models/webauthn_challenge.rb spec/models/webauthn_challenge_spec.rb
git commit -m "feat(passkeys): replay-safe WebauthnChallenge (atomic one-time consume)"
```

---

### Task 3: `WebauthnCredential` model + `users.webauthn_handle`

**Files:**
- Migrate: `*_create_webauthn_credentials.rb`, `*_add_webauthn_handle_to_users.rb`
- Create: `app/models/webauthn_credential.rb`, `spec/factories/webauthn_credentials.rb`
- Modify: `app/models/user.rb`
- Test: `spec/models/webauthn_credential_spec.rb`, `spec/models/user_spec.rb` (handle)

**Interfaces — Produces:** `User#webauthn_handle!` (race-safe lazy random handle); `User#webauthn_credentials`; `WebauthnCredential#advance_sign_count!(new_count)` (atomic; raises `Passkeys::ClonedAuthenticator` on regression); `WebauthnCredential` includes `Discardable`.

- [ ] **Step 1: Failing tests**

`spec/models/webauthn_credential_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe WebauthnCredential do
  let(:credential) { create(:webauthn_credential, sign_count: 5) }

  it "advances sign_count and records last_used_at" do
    credential.advance_sign_count!(6)
    expect(credential.reload.sign_count).to eq(6)
    expect(credential.last_used_at).to be_present
  end

  it "raises ClonedAuthenticator when the count does not advance" do
    expect { credential.advance_sign_count!(5) }.to raise_error(Passkeys::ClonedAuthenticator)
    expect(credential.reload.sign_count).to eq(5)
  end

  it "is discardable (kept scope excludes discarded)" do
    credential.discard!
    expect(WebauthnCredential.kept).not_to include(credential)
  end
end
```

`spec/models/user_spec.rb` (add):

```ruby
describe "#webauthn_handle!" do
  it "lazily generates a stable opaque handle" do
    user = create(:user)
    handle = user.webauthn_handle!
    expect(handle).to be_present
    expect(user.webauthn_handle!).to eq(handle) # stable on second call
  end
end
```

- [ ] **Step 2: Run red** → both fail.

- [ ] **Step 3: Migrations**

`*_create_webauthn_credentials.rb`:

```ruby
class CreateWebauthnCredentials < ActiveRecord::Migration[8.1]
  def change
    create_table :webauthn_credentials do |t|
      t.references :user, null: false, foreign_key: true
      t.string :external_id, null: false
      t.string :public_key, null: false
      t.integer :sign_count, null: false, default: 0
      t.string :nickname
      t.datetime :last_used_at
      t.datetime :verified_at
      t.datetime :discarded_at
      t.timestamps
    end
    add_index :webauthn_credentials, :external_id, unique: true
  end
end
```

`*_add_webauthn_handle_to_users.rb`:

```ruby
class AddWebauthnHandleToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :webauthn_handle, :string
    add_index :users, :webauthn_handle, unique: true
  end
end
```

Run `mise exec -- bin/rails db:migrate`.

- [ ] **Step 4: Model + factory + User**

`app/models/webauthn_credential.rb`:

```ruby
# A registered passkey. Unlike Authentication (one row per OAuth/email provider),
# this is a *capability*: register once, authenticate many. A user may have many.
# verified_at is set once at registration and never cleared; to revoke, discard.
class WebauthnCredential < ApplicationRecord
  include Discardable

  belongs_to :user
  validates :external_id, presence: true, uniqueness: true
  validates :public_key, :sign_count, presence: true

  # Atomic advance with clone detection: a single UPDATE guarded by the current
  # count, so concurrent assertions can't both "advance" past the same value. A
  # non-advance means the authenticator's counter regressed (possible clone) —
  # reject; do not auto-delete.
  def advance_sign_count!(new_count)
    rows = self.class.where(id: id).where("sign_count < ?", new_count)
             .update_all(sign_count: new_count, last_used_at: Time.current)
    raise Passkeys::ClonedAuthenticator, "sign_count did not advance (#{new_count} <= #{sign_count})" if rows.zero?
    reload
  end
end
```

`spec/factories/webauthn_credentials.rb`:

```ruby
FactoryBot.define do
  factory :webauthn_credential do
    user
    sequence(:external_id) { |n| "cred-#{n}-#{SecureRandom.urlsafe_base64(8)}" }
    public_key { SecureRandom.urlsafe_base64(64) }
    sign_count { 0 }
    nickname { "Test passkey" }
    verified_at { Time.current }
  end
end
```

In `app/models/user.rb` add the association + lazy handle (near the other `has_many`):

```ruby
has_many :webauthn_credentials, dependent: :destroy

# Opaque, stable WebAuthn user handle — never the integer PK (FIDO guidance).
# Lazily generated on first enrollment; race-safe via the unique index + retry.
def webauthn_handle!
  return webauthn_handle if webauthn_handle.present?
  update!(webauthn_handle: SecureRandom.urlsafe_base64(32))
  webauthn_handle
rescue ActiveRecord::RecordNotUnique
  reload.webauthn_handle
end
```

- [ ] **Step 5: Green + commit**

```bash
mise exec -- bundle exec rspec spec/models/webauthn_credential_spec.rb spec/models/user_spec.rb
git add db/migrate db/schema.rb app/models/webauthn_credential.rb app/models/user.rb spec/factories/webauthn_credentials.rb spec/models
git commit -m "feat(passkeys): WebauthnCredential (atomic sign_count + clone detect) + opaque user handle"
```

---

### Task 4: `Passkeys` errors + `RegisterCeremony`

**Files:**
- Create: `app/lib/passkeys/errors.rb`, `app/lib/passkeys/register_ceremony.rb`
- Test: `spec/lib/passkeys/register_ceremony_spec.rb`

**Interfaces:**
- Consumes: `WebauthnChallenge.store/consume!`, `User#webauthn_handle!`, `User#webauthn_credentials`, the `webauthn` gem.
- Produces: `Passkeys::Error` (+ `ClonedAuthenticator`, `VerificationFailed`, `CredentialAlreadyRegistered`, `ChallengeExpired`); `Passkeys::RegisterCeremony.options(user:)` → gem options (stores the challenge); `Passkeys::RegisterCeremony.verify(user:, credential_params:, nickname:)` → created `WebauthnCredential`.

- [ ] **Step 1: Failing test (with FakeClient — real crypto)**

`spec/lib/passkeys/register_ceremony_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe Passkeys::RegisterCeremony do
  let(:user) { create(:user) }
  let(:client) { WebAuthn::FakeClient.new(Passkeys.origin) }

  it "registers a credential from a real attestation" do
    options = described_class.options(user: user)
    attestation = client.create(challenge: options.challenge)

    credential = described_class.verify(user: user, credential_params: attestation, nickname: "Laptop")

    expect(credential).to be_persisted
    expect(user.webauthn_credentials.kept.count).to eq(1)
    expect(credential.nickname).to eq("Laptop")
  end

  it "rejects a replayed challenge" do
    options = described_class.options(user: user)
    attestation = client.create(challenge: options.challenge)
    described_class.verify(user: user, credential_params: attestation, nickname: "x")

    expect {
      described_class.verify(user: user, credential_params: attestation, nickname: "y")
    }.to raise_error(Passkeys::ChallengeExpired)
  end
end
```

- [ ] **Step 2: Run red** → fails (no `Passkeys::RegisterCeremony`).

- [ ] **Step 3: Implement**

`app/lib/passkeys/errors.rb`:

```ruby
module Passkeys
  class Error < StandardError; end
  class ChallengeExpired < Error; end       # missing/expired/replayed challenge
  class VerificationFailed < Error; end      # gem rejected the attestation/assertion
  class CredentialNotFound < Error; end      # assertion for an unknown/discarded credential
  class CredentialAlreadyRegistered < Error; end
  class ClonedAuthenticator < Error; end     # sign_count regression
end
```

`app/lib/passkeys/register_ceremony.rb`:

```ruby
module Passkeys
  module RegisterCeremony
    module_function

    def options(user:)
      options = WebAuthn::Credential.options_for_create(
        user: { id: user.webauthn_handle!, name: user.email_address },
        exclude: user.webauthn_credentials.kept.pluck(:external_id),
        authenticator_selection: { resident_key: "required", user_verification: "preferred" }
      )
      WebauthnChallenge.store(challenge: options.challenge, purpose: "registration", user: user)
      options
    end

    def verify(user:, credential_params:, nickname:)
      webauthn_credential = WebAuthn::Credential.from_create(credential_params)
      challenge = WebauthnChallenge.consume!(webauthn_credential.response.client_data.challenge, purpose: "registration")
      raise ChallengeExpired unless challenge

      webauthn_credential.verify(challenge.challenge)

      user.webauthn_credentials.create!(
        external_id: webauthn_credential.id,
        public_key: webauthn_credential.public_key,
        sign_count: webauthn_credential.sign_count,
        nickname: nickname.presence || "Passkey",
        verified_at: Time.current
      )
    rescue WebAuthn::Error => e
      raise VerificationFailed, e.message
    rescue ActiveRecord::RecordNotUnique
      raise CredentialAlreadyRegistered
    end
  end
end
```

> The implementer must confirm the exact accessor for the client-data challenge on the gem's `from_create` result (`webauthn_credential.response.client_data.challenge` in v3) and that `verify` raises `WebAuthn::Error` subclasses — read the `webauthn` README/source and adjust the accessor/rescue to the gem's real API if it differs. The behavioral contract (store→consume→verify→create, replay→`ChallengeExpired`) is fixed.

- [ ] **Step 4: Green** → `mise exec -- bundle exec rspec spec/lib/passkeys/register_ceremony_spec.rb`.

- [ ] **Step 5: Commit**

```bash
git add app/lib/passkeys spec/lib/passkeys/register_ceremony_spec.rb
git commit -m "feat(passkeys): registration ceremony + named errors"
```

---

### Task 5: `AuthenticateCeremony`

**Files:**
- Create: `app/lib/passkeys/authenticate_ceremony.rb`
- Test: `spec/lib/passkeys/authenticate_ceremony_spec.rb`

**Interfaces — Produces:** `Passkeys::AuthenticateCeremony.options` → gem options (stores authentication challenge); `Passkeys::AuthenticateCeremony.verify(credential_params:)` → the authenticated `User` (advances sign_count, raises on failure/clone/unknown).

- [ ] **Step 1: Failing test**

`spec/lib/passkeys/authenticate_ceremony_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe Passkeys::AuthenticateCeremony do
  let(:user) { create(:user) }
  let(:client) { WebAuthn::FakeClient.new(Passkeys.origin) }

  before do
    reg = Passkeys::RegisterCeremony.options(user: user)
    Passkeys::RegisterCeremony.verify(user: user, credential_params: client.create(challenge: reg.challenge), nickname: "k")
  end

  it "authenticates the owner from a real assertion and advances sign_count" do
    options = described_class.options
    assertion = client.get(challenge: options.challenge)
    expect(described_class.verify(credential_params: assertion)).to eq(user)
  end

  it "rejects an unknown credential" do
    other = WebAuthn::FakeClient.new(Passkeys.origin)
    options = described_class.options
    assertion = other.get(challenge: options.challenge) # never registered
    expect { described_class.verify(credential_params: assertion) }.to raise_error(Passkeys::CredentialNotFound)
  end
end
```

- [ ] **Step 2: Run red.**

- [ ] **Step 3: Implement**

`app/lib/passkeys/authenticate_ceremony.rb`:

```ruby
module Passkeys
  module AuthenticateCeremony
    module_function

    def options
      options = WebAuthn::Credential.options_for_get(user_verification: "preferred") # empty allow => discoverable/usernameless
      WebauthnChallenge.store(challenge: options.challenge, purpose: "authentication")
      options
    end

    # Returns the authenticated User. Single transaction so challenge-consume +
    # sign_count-advance are serialized.
    def verify(credential_params:)
      webauthn_credential = WebAuthn::Credential.from_get(credential_params)
      stored = WebauthnCredential.kept.find_by(external_id: webauthn_credential.id)
      raise CredentialNotFound unless stored

      ApplicationRecord.transaction do
        challenge = WebauthnChallenge.consume!(webauthn_credential.response.client_data.challenge, purpose: "authentication")
        raise ChallengeExpired unless challenge

        webauthn_credential.verify(challenge.challenge, public_key: stored.public_key, sign_count: stored.sign_count)
        stored.advance_sign_count!(webauthn_credential.sign_count) # raises ClonedAuthenticator on regression
        stored.user
      end
    rescue WebAuthn::Error => e
      raise VerificationFailed, e.message
    end
  end
end
```

- [ ] **Step 4: Green** → `mise exec -- bundle exec rspec spec/lib/passkeys/authenticate_ceremony_spec.rb`.

- [ ] **Step 5: Commit**

```bash
git add app/lib/passkeys/authenticate_ceremony.rb spec/lib/passkeys/authenticate_ceremony_spec.rb
git commit -m "feat(passkeys): authentication ceremony (sign_count advance + clone detect)"
```

---

### Task 6: Ceremony controllers + routes (JSON endpoints)

**Files:**
- Create: `app/controllers/passkeys/registrations_controller.rb`, `app/controllers/passkeys/authentications_controller.rb`
- Modify: `config/routes.rb`
- Test: `spec/requests/passkeys/registrations_spec.rb`, `spec/requests/passkeys/authentications_spec.rb`

**Interfaces — Produces:** named routes `passkeys_registration_options_path`/`_verify`, `passkeys_authentication_options_path`/`_verify`. `authentications#verify` calls `start_new_session_for` on success.

- [ ] **Step 1: Failing request specs**

`spec/requests/passkeys/authentications_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe "Passkeys::Authentications", type: :request do
  let(:user) { create(:user) }
  let(:client) { WebAuthn::FakeClient.new(Passkeys.origin) }

  before do
    reg = Passkeys::RegisterCeremony.options(user: user)
    Passkeys::RegisterCeremony.verify(user: user, credential_params: client.create(challenge: reg.challenge), nickname: "k")
  end

  it "signs the user in from a valid assertion" do
    post passkeys_authentication_options_path
    challenge = WebauthnChallenge.where(purpose: "authentication").last.challenge
    assertion = client.get(challenge: challenge)

    post passkeys_authentication_verify_path, params: assertion.to_json,
         headers: { "CONTENT_TYPE" => "application/json" }

    expect(response).to have_http_status(:ok)
    expect(cookies[:session_id]).to be_present
  end

  it "returns 422 for an unknown credential" do
    post passkeys_authentication_options_path
    challenge = WebauthnChallenge.where(purpose: "authentication").last.challenge
    assertion = WebAuthn::FakeClient.new(Passkeys.origin).get(challenge: challenge)
    post passkeys_authentication_verify_path, params: assertion.to_json, headers: { "CONTENT_TYPE" => "application/json" }
    expect(response).to have_http_status(:unprocessable_content)
  end
end
```

> Confirm the project's request-spec auth helper for the registration spec (sign the user in) by matching `spec/requests/settings/passwords_spec.rb`.

- [ ] **Step 2: Run red.**

- [ ] **Step 3: Controllers + routes**

`config/routes.rb` (near the other auth routes):

```ruby
namespace :passkeys do
  post "registration/options",   to: "registrations#options",   as: :registration_options
  post "registration/verify",    to: "registrations#verify",    as: :registration_verify
  post "authentication/options", to: "authentications#options", as: :authentication_options
  post "authentication/verify",  to: "authentications#verify",  as: :authentication_verify
end
```

`app/controllers/passkeys/registrations_controller.rb`:

```ruby
module Passkeys
  class RegistrationsController < ApplicationController
    # authenticated (adding a passkey requires being signed in)
    def options
      render json: RegisterCeremony.options(user: Current.user)
    end

    def verify
      RegisterCeremony.verify(user: Current.user, credential_params: params.to_unsafe_h, nickname: params[:nickname])
      head :created
    rescue Passkeys::Error => e
      render json: { error: passkey_error_message(e) }, status: :unprocessable_content
    end
  end
end
```

`app/controllers/passkeys/authentications_controller.rb`:

```ruby
module Passkeys
  class AuthenticationsController < ApplicationController
    allow_unauthenticated_access
    rate_limit to: 10, within: 3.minutes, only: :verify,
      with: -> { render json: { error: t("sessions.create.rate_limited") }, status: :too_many_requests }

    def options
      render json: AuthenticateCeremony.options
    end

    def verify
      user = AuthenticateCeremony.verify(credential_params: params.to_unsafe_h)
      start_new_session_for(user)
      render json: { redirect_to: after_authentication_url }
    rescue Passkeys::Error => e
      render json: { error: passkey_error_message(e) }, status: :unprocessable_content
    end
  end
end
```

Add a shared `passkey_error_message(error)` helper to `ApplicationController` (or a concern) mapping each `Passkeys::Error` subclass to its I18n key (`t("passkeys.errors.<key>")`).

- [ ] **Step 4: Green + add the error-path coverage** (replay = consumed challenge → 422; expired challenge; origin mismatch via a `FakeClient.new("https://evil.test")`; `sign_count` regression → 422) in the request spec. Run `mise exec -- bundle exec rspec spec/requests/passkeys`.

- [ ] **Step 5: Commit**

```bash
git add app/controllers/passkeys config/routes.rb app/controllers/application_controller.rb spec/requests/passkeys
git commit -m "feat(passkeys): ceremony JSON endpoints (register + authenticate)"
```

---

### Task 7: Stimulus controller + sign-in button + autofill

**Files:**
- Create: `app/javascript/controllers/webauthn_controller.js`
- Modify: `app/views/sessions/new.html.erb`, locale (`sessions.new.passkey_button`, `passkeys.errors.*`)
- Test: covered by the system smoke in Task 11 (JS isn't unit-tested here).

**Interfaces — Produces:** a `webauthn` Stimulus controller with `authenticate()` (button) + conditional-UI autofill on connect; targets `status`; values for the four endpoint URLs.

- [ ] **Step 1: Implement the controller**

`app/javascript/controllers/webauthn_controller.js` — feature-detect, base64url encode/decode, `fetch` + CSRF, map errors, announce via the `status` target, restore focus. (Auto-registered via `eagerLoadControllersFrom`.) Core shape:

```javascript
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = {
    authOptionsUrl: String, authVerifyUrl: String,
    regOptionsUrl: String, regVerifyUrl: String
  }
  static targets = ["status", "button"]

  connect() {
    if (!this.#supported) { this.element.classList.add("passkeys-unsupported"); return }
    this.#conditionalAuthenticate() // autofill; no-op if unavailable
  }

  async authenticate() {
    if (!this.#supported) return
    try {
      const options = await this.#post(this.authOptionsUrlValue)
      const assertion = await navigator.credentials.get({ publicKey: this.#decodeGet(options) })
      const result = await this.#post(this.authVerifyUrlValue, this.#encode(assertion))
      window.location = result.redirect_to
    } catch (e) { this.#handle(e) }
  }

  async #conditionalAuthenticate() {
    if (!(await window.PublicKeyCredential?.isConditionalMediationAvailable?.())) return
    try {
      const options = await this.#post(this.authOptionsUrlValue)
      const assertion = await navigator.credentials.get({ publicKey: this.#decodeGet(options), mediation: "conditional" })
      const result = await this.#post(this.authVerifyUrlValue, this.#encode(assertion))
      window.location = result.redirect_to
    } catch (e) { /* autofill cancellation is silent */ }
  }

  get #supported() { return window.isSecureContext && !!window.PublicKeyCredential }

  #handle(error) {
    const key = error.name === "NotAllowedError" ? "cancelled"
      : error.name === "NotSupportedError" ? "unsupported"
      : (error.body?.error ? null : "failed")
    this.#announce(error.body?.error || this.#message(key))
    this.hasButtonTarget && this.buttonTarget.focus()
  }
  #announce(msg) { if (this.hasStatusTarget) this.statusTarget.textContent = msg }
  // #post(url, body): fetch with X-CSRF-Token from meta[name=csrf-token], JSON;
  //   throws {body} on non-2xx. #encode/#decodeGet: base64url <-> ArrayBuffer per WebAuthn.
  //   #message(key): read from a data attribute map of localized strings.
}
```

> The implementer writes the full `#post`/`#encode`/`#decodeGet`/`#message` helpers (base64url ↔ ArrayBuffer is the standard WebAuthn JSON conversion; reference the cedarcode demo's JS). Keep it CSP-safe (no inline handlers) and minimal.

- [ ] **Step 2: Wire `sessions/new.html.erb`**

Inside the sign-in card, wrap the email field + button in `data-controller="webauthn"` with the four URL values; mark the email field `autocomplete: "username webauthn"`; add a **"Sign in with a passkey"** button (`data-action="webauthn#authenticate"`, `data-webauthn-target="button"`, `focus-ring`, 44px) and a `role="status" aria-live="polite" aria-atomic="true" data-webauthn-target="status"` region. The button is shown unconditionally; the controller hides itself when unsupported. The email/magic-link flow remains the fallback.

- [ ] **Step 3: Commit** (no automated test here — Task 11 proves it end-to-end)

```bash
git add app/javascript/controllers/webauthn_controller.js app/views/sessions/new.html.erb config/locales
git commit -m "feat(passkeys): sign-in passkey button + conditional autofill (Stimulus)"
```

---

### Task 8: Settings — list / add / remove passkeys

**Files:**
- Create: `app/controllers/settings/passkeys_controller.rb`, `app/views/settings/passkeys/index.html.erb`
- Modify: `config/routes.rb` (settings namespace), locale
- Test: `spec/requests/settings/passkeys_spec.rb`

**Interfaces — Produces:** `settings_passkeys_path` (index), `settings_passkey_path` (DELETE → soft-discard). Add uses the Task 6 registration ceremony from the page.

- [ ] **Step 1: Failing test**

`spec/requests/settings/passkeys_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe "Settings::Passkeys", type: :request do
  let(:user) { create(:user) }
  before { sign_in(user) } # match the project's request-spec auth helper

  it "lists the user's kept passkeys" do
    create(:webauthn_credential, user: user, nickname: "My Laptop")
    get settings_passkeys_path
    expect(response.body).to include("My Laptop")
  end

  it "soft-discards a passkey on destroy (magic-link remains the floor)" do
    cred = create(:webauthn_credential, user: user)
    delete settings_passkey_path(cred)
    expect(cred.reload).to be_discarded
  end
end
```

- [ ] **Step 2: Run red.**

- [ ] **Step 3: Controller + route + view**

`config/routes.rb` settings namespace: `resources :passkeys, only: [ :index, :destroy ]`.

`app/controllers/settings/passkeys_controller.rb`:

```ruby
module Settings
  class PasskeysController < ApplicationController
    layout "settings"
    settings_context :identity

    def index
      @passkeys = Current.user.webauthn_credentials.kept.order(:created_at)
    end

    def destroy
      Current.user.webauthn_credentials.kept.find(params[:id]).discard!
      redirect_to settings_passkeys_path, notice: t(".success")
    end
  end
end
```

View `index.html.erb`: header + an "Add a passkey" trigger wired to `data-controller="webauthn"` (calls registration via the ceremony controller, capturing a nickname) + a semantic list of credentials (nickname + `last_used_at`), each with a remove control via `UI::AlertDialogComponent` (destructive confirm) and `aria-label="Remove passkey: <nickname>"`; empty state. Match `settings/connected_accounts/index.html.erb` idiom (44px targets, `focus-ring`).

- [ ] **Step 4: Green + commit**

```bash
mise exec -- bundle exec rspec spec/requests/settings/passkeys_spec.rb
git add app/controllers/settings/passkeys_controller.rb app/views/settings/passkeys config/routes.rb config/locales
git commit -m "feat(passkeys): settings management (list/add/remove, soft-delete)"
```

---

### Task 9: One-time enrollment interstitial

**Files:**
- Migrate: `*_add_passkey_prompt_seen_at_to_users.rb`
- Create: `app/views/shared/_passkey_enrollment_interstitial.html.erb`
- Modify: the authenticated layout (render the partial when eligible), `config/routes.rb` (+ a dismiss endpoint), `app/controllers/...` (dismiss action), locale
- Test: `spec/requests/passkey_prompt_spec.rb`

**Interfaces — Produces:** `User#passkey_prompt_eligible?` (no kept passkeys && `passkey_prompt_seen_at` nil); a `PATCH` dismiss endpoint stamping `passkey_prompt_seen_at`.

- [ ] **Step 1: Failing test**

`spec/requests/passkey_prompt_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe "Passkey enrollment prompt", type: :request do
  let(:user) { create(:user) }
  before { sign_in(user) }

  it "shows the interstitial on first authenticated page load, then never again" do
    get root_path
    expect(response.body).to include(I18n.t("passkeys.interstitial.title"))
    patch passkey_prompt_path # dismiss / add
    get root_path
    expect(response.body).not_to include(I18n.t("passkeys.interstitial.title"))
  end

  it "does not show it once the user has a passkey" do
    create(:webauthn_credential, user: user)
    get root_path
    expect(response.body).not_to include(I18n.t("passkeys.interstitial.title"))
  end
end
```

- [ ] **Step 2: Run red.**

- [ ] **Step 3: Implement**

Migration adds `users.passkey_prompt_seen_at :datetime`. `User#passkey_prompt_eligible?` returns `passkey_prompt_seen_at.nil? && webauthn_credentials.kept.none?`. Route `resource :passkey_prompt, only: [:update]` → a controller stamping `Current.user.update!(passkey_prompt_seen_at: Time.current)` and head :ok. Render `shared/_passkey_enrollment_interstitial` in the authenticated layout `if authenticated? && Current.user.passkey_prompt_eligible?` — a `UI::DialogComponent` (open on load) titled `passkeys.interstitial.title`, with "Add a passkey" (wires the `webauthn` controller's register flow) and "Not now" (both stamp via the dismiss endpoint). The `webauthn` controller hides it when unsupported.

- [ ] **Step 4: Green + commit**

```bash
mise exec -- bundle exec rspec spec/requests/passkey_prompt_spec.rb
git add db/migrate db/schema.rb app/models/user.rb app/views/shared/_passkey_enrollment_interstitial.html.erb app/views/layouts config/routes.rb app/controllers config/locales spec/requests/passkey_prompt_spec.rb
git commit -m "feat(passkeys): one-time post-sign-in enrollment interstitial"
```

---

### Task 10: Documentation

**Files:**
- Create: `app/docs/passkeys.md`
- Modify: `config/initializers/markdowndocs.rb` (add `passkeys` to a category)
- Test: `spec/docs/index_coverage_spec.rb` (already enforces categorization — must stay green)

- [ ] **Step 1:** Write `app/docs/passkeys.md` (front-matter `title`/`description`/`keywords`/`audience`): what passkeys are + the magic-link fallback; **RP ID/origin config** per environment incl. the new-domain caveat (old passkeys invalidate → re-register, magic-link covers it); **local HTTPS** testing (`WEBAUTHN_ORIGIN`, `bin/rails s --ssl`/tunnel, secure-context requirement); managing passkeys in settings; a troubleshooting table; browser-support note.
- [ ] **Step 2:** Add `passkeys` to the `"Guides"` array in `config/initializers/markdowndocs.rb`.
- [ ] **Step 3:** `mise exec -- bundle exec rspec spec/docs/index_coverage_spec.rb` + `mise exec -- bundle exec rake markdown:check` green.
- [ ] **Step 4: Commit** — `docs(passkeys): add /docs/passkeys (config, local HTTPS, troubleshooting)`.

---

### Task 11: System specs (virtual authenticator) + AAA + full suite

**Files:**
- Create: `spec/support/webauthn_virtual_authenticator.rb`, `spec/system/passkey_auth_spec.rb`
- Test: the system specs + full suite

**Interfaces — Consumes:** Playwright CDP virtual authenticator via `with_playwright_page`.

- [ ] **Step 1: Virtual-authenticator helper**

`spec/support/webauthn_virtual_authenticator.rb` — enable a CDP virtual authenticator on the Playwright page (`WebAuthn.enable` + `WebAuthn.addVirtualAuthenticator` via `playwright_page.context`/CDP session: protocol `ctap2`, transport `internal`, `hasResidentKey: true`, `isUserVerified: true`). Expose `with_virtual_authenticator { ... }`. Include for `type: :system`. (Reference: Playwright's `CDPSession` `WebAuthn.addVirtualAuthenticator`.)

- [ ] **Step 2: System specs**

`spec/system/passkey_auth_spec.rb` (match `spec/system/passwordless_auth_spec.rb` idiom):

```ruby
require "rails_helper"

RSpec.describe "Passkeys", type: :system do
  it "registers a passkey in settings and signs in with it" do
    user = create(:user)
    with_virtual_authenticator do
      sign_in_via_form(user)                 # magic-link helper (Phase A)
      visit settings_passkeys_path
      # add a passkey via the dialog -> navigator.credentials.create (virtual authenticator auto-approves)
      # ... fill nickname, submit
      expect(page).to have_text("Test passkey").or have_text(user.email_address)
      expect(user.webauthn_credentials.kept.count).to eq(1)
      expect(axe_clean_in_both_themes?).to eq(true) # AAA, CI

      # sign out, then sign in with the passkey button
      # ... click "Sign in with a passkey" -> navigator.credentials.get -> lands signed in
    end
  end

  it "announces a friendly error when the ceremony is cancelled" do
    # configure the virtual authenticator to reject, click the button, assert the aria-live status text
  end
end
```

- [ ] **Step 3: Run system specs + full suite**

`mise exec -- bundle exec rspec spec/system/passkey_auth_spec.rb`, then `mise exec -- bundle exec rspec`. **0 failures.** Debug stalls via `log/test.log`. If a flow proves untestable in Playwright, document it and lean on the Task 4–6 request-level coverage.

- [ ] **Step 4: Commit + finish**

```bash
git add spec/support/webauthn_virtual_authenticator.rb spec/system/passkey_auth_spec.rb
git commit -m "test(passkeys): virtual-authenticator system specs + AAA"
```

Then verify the touched screens (sign-in, settings/passkeys, interstitial) in both themes via the implementation-verifier, and hand off via `superpowers:finishing-a-development-branch`.

---

## Self-Review

**Spec coverage:** library + RP/origin seam → T1; WebauthnChallenge (replay-safe) → T2; WebauthnCredential + atomic sign_count/clone + opaque handle + soft-delete → T3; named errors + register ceremony → T4; authenticate ceremony → T5; ceremony endpoints + start_new_session_for + error paths → T6; button + autofill + a11y status + feature detection → T7; settings list/add/remove → T8; one-time interstitial → T9; docs (RP-id/local-HTTPS) → T10; virtual-authenticator system specs + AAA + full suite → T11. ✓

**Placeholder scan:** code steps carry real code; three steps explicitly instruct the implementer to confirm a gem accessor (`response.client_data.challenge`), the project's request-spec `sign_in` helper, and the base64url JS helpers against named references — these are *verification-against-reality* directives, not placeholders; the behavioral contracts are concrete.

**Type/name consistency:** `Passkeys::` namespace for ceremonies/errors (never `Webauthn::`); models `WebauthnCredential`/`WebauthnChallenge`; `WebauthnChallenge.store/consume!(challenge, purpose:)`; `User#webauthn_handle!`; `WebauthnCredential#advance_sign_count!`; ceremony methods `options`/`verify` consistent across T4–T6; route helpers `passkeys_authentication_options_path` etc. used consistently.

**Open risks for the implementer:** the gem's exact v3 accessor for the response challenge + which `WebAuthn::Error` subclasses `verify` raises (T4/T5); the Playwright CDP virtual-authenticator API (T11 — stand it up early, it gates the system smoke); `webauthn` on the boot path (mirror into Rails-booting CI jobs).
