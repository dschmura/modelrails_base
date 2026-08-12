class WorkspaceIdentity < Identity
  def image = model.logo
  def image_original = model.logo_original
  def source = model.logo_source
  def available_sources = model.available_logo_sources
end
