# frozen_string_literal: true

namespace :tailwind do
  desc "Create symlinks for gem view sources so Tailwind can scan them portably"
  task setup_gem_sources: :environment do
    vendor_dir = Rails.root.join("vendor")
    FileUtils.mkdir_p(vendor_dir)

    markdowndocs_path = Gem.loaded_specs["markdowndocs"]&.full_gem_path
    if markdowndocs_path
      target = vendor_dir.join("markdowndocs_views")
      source = File.join(markdowndocs_path, "app/views")
      FileUtils.ln_sf(source, target)
      puts "Linked #{target} → #{source}"
    end
  end
end
