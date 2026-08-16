class ApplicationRecord < ActiveRecord::Base
  primary_abstract_class

  # Content types accepted for user-supplied images (avatars, workspace logos).
  # Deliberately WIDER than ActiveStorage.web_image_content_types — HEIC/HEIF
  # (the iPhone camera default) stay in. One shared list, not per-model copies:
  # drift between copies is how #496 happened.
  # See /docs/developer/security (Image Processing).
  IMAGE_CONTENT_TYPES = %w[
    image/png
    image/jpeg
    image/gif
    image/webp
    image/heic
    image/heif
  ].freeze
end
