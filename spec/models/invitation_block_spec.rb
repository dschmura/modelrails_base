require "rails_helper"

RSpec.describe InvitationBlock, type: :model do
  let(:inviter) { create(:user) }

  describe "validations" do
    it "requires a well-formed email" do
      expect(build(:invitation_block, inviter: inviter, email: "not-an-email")).not_to be_valid
      expect(build(:invitation_block, inviter: inviter, email: "")).not_to be_valid
      expect(build(:invitation_block, inviter: inviter, email: "ok@example.com")).to be_valid
    end

    it "enforces uniqueness per inviter at the validation layer too" do
      create(:invitation_block, inviter: inviter, email: "dup@example.com")
      expect(build(:invitation_block, inviter: inviter, email: "dup@example.com")).not_to be_valid
      expect(build(:invitation_block, inviter: create(:user), email: "dup@example.com")).to be_valid
    end
  end

  describe "encryption (T2)" do
    it "stores ciphertext, not the address" do
      block = create(:invitation_block, inviter: inviter, email: "secret@example.com")
      raw = ActiveRecord::Base.connection.select_value(
        "SELECT email FROM invitation_blocks WHERE id = #{block.id}"
      )
      expect(raw).not_to include("secret@example.com")
      expect(InvitationBlock.find_by(email: "secret@example.com")).to eq(block)
    end

    it "downcases at the cipher on a write that skips the normalizes decoration" do
      # Bare type shares the column's scheme but not its `normalizes` decoration —
      # proves `downcase:` is a cipher-level guarantee, not something `normalizes`
      # provides (design spec §5/T2's "hole" framing is wrong; corrected in this
      # commit's message).
      block = create(:invitation_block, inviter: inviter, email: "placeholder@example.com")
      bare_type = ActiveRecord::Encryption::EncryptedAttributeType.new(
        scheme: InvitationBlock.type_for_attribute(:email).scheme
      )
      ciphertext = bare_type.serialize("MiXeD@Example.COM")
      ActiveRecord::Base.connection.execute(
        "UPDATE invitation_blocks SET email = #{ActiveRecord::Base.connection.quote(ciphertext)} WHERE id = #{block.id}"
      )
      expect(InvitationBlock.find_by(email: "mixed@example.com")).to be_present
    end
  end

  describe "normalization (Ruling T1-1)" do
    it "strips surrounding whitespace before validation and encryption" do
      # Pins the behavior `normalizes` uniquely adds (strip/NFC — see
      # app/lib/email_normalizer.rb) that `downcase:` at the cipher does not cover:
      # without `normalizes`, this padded input fails User::EMAIL_FORMAT outright.
      block = create(:invitation_block, inviter: inviter, email: "  Pad@Example.COM  ")
      expect(InvitationBlock.find_by(email: "pad@example.com")).to eq(block)
    end
  end

  describe "creation writes no activity rows (T27, model half)" do
    it "leaves the ActivityLog table untouched" do
      # Force the let outside the block: create(:user)'s own onboarding
      # (workspace + membership) writes Trackable activity rows of its own.
      inviter
      expect { create(:invitation_block, inviter: inviter, email: "quiet@example.com") }
        .not_to change(ActivityLog, :count)
    end
  end
end
