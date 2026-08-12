# Visual identity of a User (avatar) or Workspace (logo): one polymorphic
# surface over the differently-named attachment/source/color attributes, so
# shared views and the picker write flow never type-switch on the model.
# NOT OauthIdentity (same directory) — that is the *authentication* identity
# (provider/uid). Design: docs repo, specs/2026-08-12-identity-poro-design.md.
class Identity
  DEFAULT_HUE = 210

  def initialize(model)
    @model = model
  end

  def initials = model.initials
  def primary_color = model.primary_color
  def hue = primary_color || DEFAULT_HUE
  def image? = image.attached?

  def image_updated_at
    image? ? image.blob.created_at : nil
  end

  # Re-crop source: the original when stored, so quality isn't progressively
  # degraded; falls back to the cropped image for older records.
  def croppable_image
    image_original.attached? ? image_original : image
  end

  def gravatar_url(size: 256) = nil

  def resolve_source(requested)
    return source if requested.blank?
    available_sources.include?(requested) ? requested : source
  end

  private

  attr_reader :model
end
