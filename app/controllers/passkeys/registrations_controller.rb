# frozen_string_literal: true

module Passkeys
  # Authenticated endpoints for adding a passkey to the current user's account.
  # Requires an active session — unauthenticated requests are redirected to sign-in
  # by the default Authenticatable before_action.
  class RegistrationsController < ApplicationController
    def options
      render json: RegisterCeremony.options(user: Current.user)
    end

    def verify
      begin
        RegisterCeremony.verify(
          user: Current.user,
          credential_params: params.to_unsafe_h,
          nickname: params[:nickname]
        )
      rescue ArgumentError
        # WebAuthn gem raises ArgumentError for malformed base64 in credential JSON
        raise Passkeys::VerificationFailed
      end
      render json: { redirect_to: settings_passkeys_path }, status: :created
    rescue Passkeys::Error => e
      render json: { error: passkey_error_message(e) }, status: :unprocessable_content
    end
  end
end
