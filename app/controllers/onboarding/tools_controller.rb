module Onboarding
  # Forward-only interstitial between the project and team steps. Self-hides:
  # ProjectsController#create only routes here when the registry offers a real
  # choice (>1 toggleable tool). The resume dispatcher never sends users here —
  # tool selection is optional and falls back to the create-time defaults.
  class ToolsController < BaseController
    before_action :require_project

    def new
      authorize @project, :update?
      @tools = ProjectTools::Registry.toggleable
    end

    def create
      authorize @project, :update?

      allowed = ProjectTools::Registry.toggleable.map { |t| t.key.to_s }
      selected = Array(params.dig(:project, :enabled_tools)) & allowed
      @project.update!(enabled_tools: selected)

      redirect_to new_onboarding_team_path
    end

    private

    def require_project
      @project = Current.workspace&.projects&.kept&.first
      redirect_to onboarding_path if @project.nil?
    end
  end
end
