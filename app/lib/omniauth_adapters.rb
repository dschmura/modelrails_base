# Maps OmniAuth strategy names to canonical Authentication#provider enum values,
# so the controller stays focused on flow logic rather than naming-quirk
# normalization.
module OmniauthAdapters
  PROVIDER_MAP = { "google_oauth2" => "google" }.freeze

  def self.normalize_provider(strategy_name)
    PROVIDER_MAP.fetch(strategy_name, strategy_name)
  end
end
