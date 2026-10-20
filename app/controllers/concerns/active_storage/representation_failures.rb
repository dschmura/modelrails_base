# A variant that cannot be processed answers its image request, never 500s it: permanent failures redirect to a
# placeholder that may be cached, transient ones answer 503 so the browser asks again. /docs/developer/security
module ActiveStorage::RepresentationFailures
  extend ActiveSupport::Concern

  included do
    rescue_from "HotCell::PermanentFailure", "Vips::Error", with: :representation_unavailable
    rescue_from "HotCell::TransientFailure", with: :representation_pending
  end

  private
    def representation_unavailable
      expires_in 100.years, public: true
      redirect_to helpers.asset_path("representation-unavailable.svg")
    end

    def representation_pending
      response.headers["Cache-Control"] = "no-store"
      response.headers["Retry-After"] = "5"
      head :service_unavailable
    end
end
