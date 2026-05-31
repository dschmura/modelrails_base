# frozen_string_literal: true

# Lookbook — interactive component explorer / living docs for modelrails_ui (dev-only).
# Mounted at /lookbook (see config/routes.rb). Previews live in spec/components/previews.
# ViewComponent 4 nests preview config under `previews`.
if Rails.env.development?
  vc = Rails.application.config.view_component
  preview_dir = Rails.root.join("spec/components/previews").to_s
  vc.previews.paths = Array(vc.previews.paths) | [ preview_dir ]
  vc.previews.default_layout = "component_preview"
  # Lookbook keeps its OWN preview_paths (separate from ViewComponent's).
  Rails.application.config.lookbook.preview_paths = [ preview_dir ]
end
