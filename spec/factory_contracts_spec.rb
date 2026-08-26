require "rails_helper"

# The `:user` factory used to build a user with no `authentications` row — a
# state no production path can produce. Every signup creates one: magic-link
# registration stamps it verified (the mailbox round trip is the proof), and
# password-set creates it pending on purpose.
#
# `User#can_invite?` asks for a verified authentication, so a bare factory user
# answered false, and the trait that fixed it had to be remembered by every
# author who needed the universal case. That is backwards, and it cost a round
# of analysis in #842 when a fixture gap read as a product bug.
#
# These pin the default and the two escapes, so the exceptional states stay
# reachable and stay named (#850).
RSpec.describe "the :user factory" do
  it "gives a user the verified email authentication every signup produces" do
    auth = create(:user).authentications.sole

    expect(auth.provider).to eq("email")
    expect(auth).to be_verified
  end

  it "uses the user's own address as the authentication uid, as production does" do
    user = create(:user)

    expect(user.authentications.sole.uid).to eq(user.email_address)
  end

  it "produces a user who can invite, with no trait to remember" do
    expect(create(:user)).to be_can_invite
  end

  describe ":unverified_email" do
    it "leaves the authentication pending, like password-set does" do
      user = create(:user, :unverified_email)

      expect(user.authentications.sole).not_to be_verified
      expect(user).not_to be_can_invite
    end
  end

  it "attaches the authentication on create only — build(:user) carries none" do
    user = build(:user)

    expect(user.authentications).to be_empty
    expect(user).not_to be_can_invite
  end

  it "refuses an unknown email_authentication value instead of guessing" do
    expect { create(:user, email_authentication: :unverified) }
      .to raise_error(ArgumentError, /:verified, :pending or :none/)
  end

  it "resolves combined traits by last-trait-wins, FactoryBot's documented precedence" do
    expect(create(:user, :unverified_email, :no_authentications).authentications).to be_empty
    expect(create(:user, :no_authentications, :unverified_email).authentications.sole).not_to be_verified
  end

  describe ":no_authentications" do
    it "builds the account with none at all, for specs about that edge" do
      user = create(:user, :no_authentications)

      expect(user.authentications).to be_empty
      expect(user).not_to be_can_invite
    end
  end
end
