FactoryBot.define do
  factory :operatorship do
    user
    granted_by factory: :user
  end
end
