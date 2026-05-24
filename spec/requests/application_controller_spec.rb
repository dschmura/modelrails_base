require "rails_helper"

RSpec.describe "ApplicationController#signups_open?", type: :request do
  context "when SIGNUP_MODE is :invite_only with a valid token in session" do
    let(:invitation) { create(:invitation) }

    before do
      allow(Rails.configuration.x.signup).to receive(:mode).and_return(:invite_only)
    end

    it "memoizes signups_open? on the controller instance" do
      # Visit the invitation acceptance route to stash the token in session.
      get accept_invitation_path(token: invitation.token)

      # Spy on the policy method to count how many times it's called per request.
      call_count = 0
      allow(SignupPolicy).to receive(:allows_signup?).and_wrap_original do |original, **kwargs|
        call_count += 1
        original.call(**kwargs)
      end

      get root_path

      # signups_open? may be called by the landing page partials. Whether 0 or 1,
      # it must never exceed 1 per request thanks to memoization.
      expect(call_count).to be <= 1
    end
  end
end
