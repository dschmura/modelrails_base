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

    trait :passkey_prompt_pending do
      passkey_prompt_seen_at { nil }
    end

    trait :with_email_auth do
      after(:create) do |user|
        user.authentications.find_or_create_by!(provider: "email") do |auth|
          auth.uid = user.email_address
        end
      end
    end

    trait :with_avatar do
      after(:create) do |user|
        fixture = Rails.root.join("spec/fixtures/files/avatar.png")
        user.avatar.attach(io: File.open(fixture), filename: "avatar.png", content_type: "image/png")
        user.avatar_original.attach(io: File.open(fixture), filename: "original.png", content_type: "image/png")
        user.update!(avatar_source: "upload")
      end
    end

    # Silences the after_create :onboard_workspace callback for THIS instance
    # so the user persists with zero workspaces and no personal_workspace_id.
    # Used by zero-workspace crash-safety specs. The singleton override is
    # instance-scoped and does not leak to other factory calls.
    trait :with_zero_workspaces do
      after(:build) do |user|
        user.define_singleton_method(:onboard_workspace) { nil }
      end
    end
  end
end
