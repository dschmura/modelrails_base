FactoryBot.define do
  factory :user do
    email_address { Faker::Internet.email }
    password { "SecureP@ssw0rd123!" }
    first_name { Faker::Name.first_name }
    last_name { Faker::Name.last_name }
    # Default: already-onboarded user — the passkey enrollment banner will not
    # appear, keeping it out of the system specs that don't test it. (The banner
    # is non-blocking; this just avoids incidental noise.)
    passkey_prompt_seen_at { Time.current }

    # Every production signup creates an email authentication: magic-link
    # registration stamps it verified (the mailbox round trip is the proof),
    # password-set creates it pending on purpose. A user with none is a state
    # the app cannot reach, so it is the default here rather than a trait
    # somebody has to remember — the exceptional states are named instead.
    #
    # Carried as a transient rather than trait-local callbacks so the outcome
    # does not depend on the order FactoryBot applies traits in (#850).
    transient do
      email_authentication { :verified }
    end

    after(:create) do |user, evaluator|
      next if evaluator.email_authentication == :none

      user.authentications.find_or_create_by!(provider: "email") do |auth|
        auth.uid = user.email_address
        auth.verified_at = Time.current if evaluator.email_authentication == :verified
      end
    end

    trait :passkey_prompt_pending do
      passkey_prompt_seen_at { nil }
    end

    # Magic-link / OAuth-only account — the common case in a passwordless-first
    # app, and the reason re-auth can't assume a password.
    trait :passwordless do
      password { nil }
      password_digest { nil }
    end

    # Has an address on file but has not proven it — what password-set alone
    # produces. Cannot invite.
    trait :unverified_email do
      email_authentication { :pending }
    end

    # No authentications row at all. Production cannot reach this; it exists
    # for the specs that are ABOUT its absence.
    trait :no_authentications do
      email_authentication { :none }
    end

    trait :with_avatar do
      after(:create) do |user|
        fixture = Rails.root.join("spec/fixtures/files/avatar.png")
        user.avatar.attach(io: File.open(fixture), filename: "avatar.png", content_type: "image/png")
        user.avatar_original.attach(io: File.open(fixture), filename: "original.png", content_type: "image/png")
        user.update!(avatar_source: "upload")
      end
    end

    trait :with_gravatar do
      has_gravatar { true }
    end

    # Persists the user with zero workspaces and no personal_workspace_id by
    # saving under the :none tenancy posture — the real production branch of
    # onboard_workspace, not a stubbed-out callback. Scoped to THIS create
    # (config restored in ensure), so other factory calls in the same example
    # still onboard normally. Used by zero-workspace crash-safety specs.
    trait :with_zero_workspaces do
      to_create do |user|
        original = Rails.configuration.x.tenancy.onboarding
        Rails.configuration.x.tenancy.onboarding = :none
        begin
          user.save!
        ensure
          Rails.configuration.x.tenancy.onboarding = original
        end
      end
    end
  end
end
