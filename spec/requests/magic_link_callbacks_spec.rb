require "rails_helper"

RSpec.describe "Magic Link Callbacks", type: :request do
  describe "GET /magic_link_callback/:token" do
    context "valid token for existing user" do
      let(:user) { create(:user) }
      let(:token) { MagicLinkToken.create_for_email(user.email_address) }

      it "signs in the user and redirects to root" do
        get magic_link_callback_path(token: token)
        expect(response).to redirect_to(root_path)
      end

      it "consumes the token" do
        get magic_link_callback_path(token: token)
        token_record = MagicLinkToken.find_by(token: token)
        expect(token_record.consumed_at).to be_present
      end

      it "sets a signed-in notice" do
        get magic_link_callback_path(token: token)
        expect(flash[:notice]).to be_present
      end
    end

    context "valid token for new email (no existing user)" do
      let(:token) { MagicLinkToken.create_for_email("brand-new@example.com") }

      it "renders the registration form" do
        get magic_link_callback_path(token: token)
        expect(response).to have_http_status(:ok)
        expect(response.body).to include(I18n.t("magic_link_callbacks.new_registration.title"))
      end

      it "does not consume the token" do
        get magic_link_callback_path(token: token)
        token_record = MagicLinkToken.find_by(token: token)
        expect(token_record.consumed_at).to be_nil
      end
    end

    context "invalid token" do
      it "redirects to sign in with an alert" do
        get magic_link_callback_path(token: "totally-bogus-token")
        expect(response).to redirect_to(new_session_path)
        expect(flash[:alert]).to be_present
      end
    end

    context "already-consumed token" do
      let(:user) { create(:user) }

      it "redirects to sign in" do
        token = MagicLinkToken.create_for_email(user.email_address)
        MagicLinkToken.find_by(token: token).consume!
        get magic_link_callback_path(token: token)
        expect(response).to redirect_to(new_session_path)
        expect(flash[:alert]).to be_present
      end
    end

    context "expired token" do
      let(:user) { create(:user) }

      it "redirects to sign in" do
        token = MagicLinkToken.create_for_email(user.email_address)
        MagicLinkToken.find_by(token: token).update!(expires_at: 1.hour.ago)
        get magic_link_callback_path(token: token)
        expect(response).to redirect_to(new_session_path)
        expect(flash[:alert]).to be_present
      end
    end
  end

  describe "POST /magic_link_callback/:token" do
    context "valid token and valid user params" do
      before { allow(Rails.configuration.x.signup).to receive(:mode).and_return(:open) }
      let(:token) { MagicLinkToken.create_for_email("newreg@example.com") }

      it "creates the user" do
        expect {
          post magic_link_callback_path(token: token), params: {
            user: { first_name: "Jane", last_name: "Doe" }
          }
        }.to change(User, :count).by(1)
      end

      it "creates a verified email authentication" do
        post magic_link_callback_path(token: token), params: {
          user: { first_name: "Jane", last_name: "Doe" }
        }
        user = User.find_by(email_address: "newreg@example.com")
        auth = user.authentications.find_by(provider: "email")
        expect(auth).to be_present
        expect(auth.verified_at).to be_present
      end

      it "consumes the token" do
        post magic_link_callback_path(token: token), params: {
          user: { first_name: "Jane", last_name: "Doe" }
        }
        token_record = MagicLinkToken.find_by(token: token)
        expect(token_record.consumed_at).to be_present
      end

      it "signs in and redirects to root" do
        post magic_link_callback_path(token: token), params: {
          user: { first_name: "Jane", last_name: "Doe" }
        }
        expect(response).to redirect_to(root_path)
      end
    end

    context "valid token but invalid user params" do
      before { allow(Rails.configuration.x.signup).to receive(:mode).and_return(:open) }
      let(:token) { MagicLinkToken.create_for_email("baddatauser@example.com") }

      it "returns unprocessable entity for blank first_name" do
        post magic_link_callback_path(token: token), params: {
          user: { first_name: "", last_name: "Doe" }
        }
        expect(response).to have_http_status(:unprocessable_entity)
      end

      it "re-renders the registration form" do
        post magic_link_callback_path(token: token), params: {
          user: { first_name: "", last_name: "Doe" }
        }
        expect(response.body).to include(I18n.t("magic_link_callbacks.new_registration.title"))
      end

      it "does not consume the token" do
        post magic_link_callback_path(token: token), params: {
          user: { first_name: "", last_name: "Doe" }
        }
        token_record = MagicLinkToken.find_by(token: token)
        expect(token_record.consumed_at).to be_nil
      end
    end

    context "invalid token" do
      it "redirects to sign in" do
        post magic_link_callback_path(token: "garbage"), params: {
          user: { first_name: "Jane", last_name: "Doe" }
        }
        expect(response).to redirect_to(new_session_path)
        expect(flash[:alert]).to be_present
      end
    end

    context "already-consumed token" do
      it "redirects to sign in" do
        token = MagicLinkToken.create_for_email("consumed-reg@example.com")
        MagicLinkToken.find_by(token: token).consume!
        post magic_link_callback_path(token: token), params: {
          user: { first_name: "Test", last_name: "User" }
        }
        expect(response).to redirect_to(new_session_path)
        expect(flash[:alert]).to be_present
      end
    end
  end

  describe "POST /magic_link_callback/:token (new-user signup)" do
    let(:workspace) { create(:workspace) }
    let(:token_record) { create(:magic_link_token, email: "newml@example.com") }
    let(:params) { { user: { first_name: "Magic", last_name: "Link" } } }

    context "in invite_only mode without an invitation token in session" do
      before { allow(Rails.configuration.x.signup).to receive(:mode).and_return(:invite_only) }

      it "redirects to new_registration_path with 303 and creates no User" do
        expect {
          post magic_link_callback_path(token: token_record.token), params: params
        }.not_to change(User, :count)

        expect(response).to redirect_to(new_registration_path)
        expect(response).to have_http_status(:see_other)
        expect(flash[:alert]).to include(I18n.t("registrations.closed.oauth_blocked"))
      end

      it "does NOT consume the magic-link token" do
        post magic_link_callback_path(token: token_record.token), params: params
        expect(token_record.reload.consumed_at).to be_nil
      end
    end

    context "in invite_only mode with a valid invitation token in session" do
      let(:invitation) { create(:invitation, invitable: workspace, email: "newml@example.com") }

      before do
        allow(Rails.configuration.x.signup).to receive(:mode).and_return(:invite_only)
        # POST to the invitation acceptance route — sets session[:pending_invitation_token]
        post accept_invitation_path(token: invitation.token)
      end

      it "creates the user, consumes the token, accepts the invitation" do
        expect {
          post magic_link_callback_path(token: token_record.token), params: params
        }.to change(User, :count).by(1)

        expect(token_record.reload.consumed_at).to be_present
        expect(invitation.reload).to be_accepted

        new_user = User.find_by(email_address: "newml@example.com")
        expect(new_user.workspaces).to include(workspace)
      end
    end

    context "when the magic-link token gets consumed concurrently (race)" do
      let(:invitation) { create(:invitation, invitable: workspace, email: "newml@example.com") }

      before do
        allow(Rails.configuration.x.signup).to receive(:mode).and_return(:invite_only)
        # POST to the invitation acceptance route — sets session[:pending_invitation_token]
        post accept_invitation_path(token: invitation.token)
        # Simulate concurrent consumption (returns nil to indicate race-lost)
        allow(MagicLinkToken).to receive(:consume!).and_return(nil)
      end

      it "rolls back user creation when token consume returns nil" do
        expect {
          post magic_link_callback_path(token: token_record.token), params: params
        }.not_to change(User, :count)

        expect(invitation.reload).to be_pending
      end
    end
  end
end
