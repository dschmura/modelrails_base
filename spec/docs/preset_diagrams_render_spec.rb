require "rails_helper"

# Guards that the inline-SVG "How users relate" diagrams actually render on each
# preset page — i.e. markdowndocs `config.allow_svg` is enabled AND the gem
# preserves the SVG through its pipeline. If the gem regresses, allow_svg is
# removed, or the gem is downgraded below 0.8.0, the SafeListSanitizer strips
# the <svg> and these fail loudly instead of the diagrams silently vanishing.
RSpec.describe "Preset relationship diagrams", type: :request do
  {
    "presets-open-saas" => "arrow-open-saas",
    "presets-single-tenant" => "arrow-single-tenant",
    "presets-solo" => "arrow-solo"
  }.each do |slug, marker_id|
    it "renders the inline SVG diagram on /docs/#{slug}" do
      get "/docs/#{slug}"

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("<svg")
      # camelCase viewBox must survive — guards the Nokogiri::HTML5 parsing fix
      # (Nokogiri::HTML would lowercase it to `viewbox`, breaking scaling).
      expect(response.body).to match(/viewBox="0 0 7\d\d /)
      # the per-diagram arrowhead marker must survive sanitization and keep its
      # unique id (no cross-diagram collision).
      expect(response.body).to include(%(id="#{marker_id}"))
    end
  end
end
