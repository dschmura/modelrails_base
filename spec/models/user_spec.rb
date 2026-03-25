require "rails_helper"

RSpec.describe User, type: :model do
  describe "validations" do
    it "requires an email address" do
      user = User.new(email_address: nil)
      expect(user).not_to be_valid
      expect(user.errors[:email_address]).to be_present
    end

    it "requires a unique email address" do
      create(:user, email_address: "test@example.com")
      duplicate = build(:user, email_address: "test@example.com")
      expect(duplicate).not_to be_valid
    end

    it "normalizes email to lowercase" do
      user = create(:user, email_address: "Test@Example.COM")
      expect(user.email_address).to eq("test@example.com")
    end
  end

  describe "associations" do
    it "has many sessions" do
      expect(User.reflect_on_association(:sessions).macro).to eq(:has_many)
    end
  end
end
