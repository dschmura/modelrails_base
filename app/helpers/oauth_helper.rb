module OauthHelper
  # Reads the one provider registry (config/initializers/
  # 0_oauth_provider_registry.rb) so buttons, OmniAuth wiring, and the CSP
  # form_action can never drift apart (#312).
  PROVIDER_CONFIG = Rails.application.config.x.oauth_providers

  def enabled_oauth_providers
    PROVIDER_CONFIG.select do |provider_key, _config|
      case provider_key
      when :google_oauth2
        Rails.application.credentials.dig(:oauth, :google, :client_id).present?
      when :github
        Rails.application.credentials.dig(:oauth, :github, :client_id).present?
      end
    end
  end

  def oauth_enabled?
    enabled_oauth_providers.any?
  end
end
