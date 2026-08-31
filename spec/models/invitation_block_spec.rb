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

    it "matches a raw-SQL-written mixed-case row (the hole downcase: covers)" do
      # `normalizes` decorates the attribute TYPE itself (ActiveModel::Attributes::
      # Normalization#normalizes), so insert_all/update_all still route through it —
      # verified against this Rails version; it is NOT the "bypasses normalizes" hole
      # the design spec's §5/T2 wording describes (flagged in this task's commit).
      # The real hole is a row an application write never touches at all — a raw SQL
      # backfill/import — which is exactly what Rails' own `normalizes` docs call out
      # ("if a record was persisted before the normalization was declared..."). Build
      # that ciphertext with a bare type sharing the column's scheme (so it skips the
      # `normalizes` decoration entirely) and land it with a raw UPDATE, bypassing
      # ActiveRecord's attribute type system on write the way that import would.
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
