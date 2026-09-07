require "rails_helper"

# Post-sign-in landing is workspace-agnostic and fork-overridable. The template
# default routes an authenticated user with no saved return_to to their home
# (authenticated_home_path => root_path). A fork overrides ONE method to land
# users at a fork-specific home (a dashboard, a profile). (organizer-onboarding
# design, Template BLOCKERS.)
RSpec.describe "Authenticated landing seam", type: :request do
  let(:user) { create(:user) }

  describe "default destination after sign-in" do
    it "lands on root when there is no saved return_to" do
      post session_path, params: { email_address: user.email_address, password: "SecureP@ssw0rd123!" }
      expect(response).to redirect_to(root_url)
    end

    it "still honors a saved return_to over the home default" do
      get edit_settings_profile_path
      expect(response).to redirect_to(new_session_path)
      post session_path, params: { email_address: user.email_address, password: "SecureP@ssw0rd123!" }
      expect(response).to redirect_to(edit_settings_profile_url)
    end
  end

  describe "the seam is overridable" do
    # The unique claim of this file: a fork overrides ONE method and every
    # sign-in path follows. Asserting the redirect target alone would not say
    # it — inlining `session.delete(:return_to_after_authenticating) ||
    # root_path` into after_authentication_url deletes the seam and still
    # passes the two examples above. Stubbing the seam and driving a REAL
    # sign-in is what fails on that change.
    #
    # allow_any_instance_of (a named smell) because the controller instance
    # is the framework's, created inside the request; there is nothing else
    # to hold. It does not verify the method exists — but a rename leaves the
    # stub inert and lands the redirect on root, which fails this example
    # anyway.
    it "sends a real sign-in wherever a fork points authenticated_home_path" do
      allow_any_instance_of(SessionsController)
        .to receive(:authenticated_home_path).and_return(page_path(:about))

      post session_path, params: { email_address: user.email_address, password: "SecureP@ssw0rd123!" }

      expect(response).to redirect_to(page_url(:about))
    end
  end
end
