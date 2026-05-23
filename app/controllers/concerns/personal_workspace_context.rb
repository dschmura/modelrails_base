module PersonalWorkspaceContext
  extend ActiveSupport::Concern

  included do
    before_action :set_personal_workspace
  end

  private

  def set_personal_workspace
    Current.workspace = Current.user&.personal_workspace
  end
end
