FactoryBot.define do
  factory :activity_log do
    actor factory: :user
    action { "test.action" }
    association :trackable, factory: :workspace
    workspace { nil }
    visibility { "workspace" }
    metadata { {} }
  end
end
