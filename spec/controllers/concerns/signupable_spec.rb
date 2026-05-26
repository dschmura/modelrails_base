require "rails_helper"

RSpec.describe Signupable, type: :controller do
  controller(ApplicationController) do
    include Signupable
    allow_unauthenticated_access

    def create
      user = User.new(
        email_address: params[:email_address],
        first_name: "Test",
        last_name: "User",
        password: "supersecret123",
        password_confirmation: "supersecret123"
      )

      if commit_signup_atomically(user) { |u| u.authentications.create!(provider: "email", uid: u.email_address) }
        render plain: "ok"
      else
        render plain: "fail", status: :unprocessable_entity
      end
    end
  end

  before do
    routes.draw { post "create" => "anonymous#create" }
  end

  describe "#commit_signup_atomically" do
    it "returns true and commits when block succeeds" do
      post :create, params: { email_address: "new@example.com" }
      expect(response).to have_http_status(:ok)
      expect(User.find_by(email_address: "new@example.com")).to be_present
    end

    it "returns false when user.save! raises RecordInvalid" do
      post :create, params: { email_address: "not an email" }
      expect(response).to have_http_status(:unprocessable_entity)
      expect(User.find_by(email_address: "not an email")).to be_nil
    end

    it "consumes the session token on success when invitation is present" do
      invitation = create(:invitation, email: "invitee@example.com")
      session[:pending_invitation_token] = invitation.token

      post :create, params: { email_address: "invitee@example.com" }

      expect(response).to have_http_status(:ok)
      expect(invitation.reload).to be_accepted
      expect(session[:pending_invitation_token]).to be_nil
    end

    it "rolls back user creation when invitation accept! raises NotAcceptable" do
      invitation = create(:invitation, :accepted)
      session[:pending_invitation_token] = invitation.token

      expect {
        post :create, params: { email_address: "racer@example.com" }
      }.not_to change(User, :count)

      expect(response).to have_http_status(:unprocessable_entity)
      expect(flash.now[:alert]).to be_present
    end

    it "leaves session token in place when invitation NotAcceptable" do
      invitation = create(:invitation, :expired)
      session[:pending_invitation_token] = invitation.token

      post :create, params: { email_address: "retry@example.com" }

      expect(session[:pending_invitation_token]).to eq(invitation.token)
    end
  end

  describe "#accept_pending_invitation!" do
    let(:user) { create(:user) }

    it "is a no-op when no token in session" do
      expect { controller.send(:accept_pending_invitation!, user) }.not_to raise_error
    end

    it "is a no-op when token does not match any invitation" do
      controller.session[:pending_invitation_token] = "no-such-token"
      controller.send(:accept_pending_invitation!, user)
      expect(controller.session[:pending_invitation_token]).to eq("no-such-token")
    end

    it "accepts and clears token on valid invitation" do
      invitation = create(:invitation)
      controller.session[:pending_invitation_token] = invitation.token
      controller.send(:accept_pending_invitation!, user)
      expect(invitation.reload).to be_accepted
      expect(controller.session[:pending_invitation_token]).to be_nil
    end
  end
end
