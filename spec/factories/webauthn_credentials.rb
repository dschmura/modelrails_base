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
