FactoryBot.define do
  factory :authentication do
    # This factory exists to create the authentication, so its user must not
    # arrive already holding one — the :user default is a verified email row,
    # and provider is unique per user (#850).
    association :user, factory: [ :user, :no_authentications ]
    provider { "email" }
    uid { Faker::Internet.email }

    trait :google do
      provider { "google" }
      uid { Faker::Number.number(digits: 21).to_s }
      oauth_token { SecureRandom.hex(32) }
    end

    trait :github do
      provider { "github" }
      uid { Faker::Number.number(digits: 8).to_s }
      oauth_token { SecureRandom.hex(32) }
    end

    trait :verified do
      verified_at { Time.current }
    end
  end
end
