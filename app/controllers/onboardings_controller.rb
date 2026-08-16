class OnboardingsController < ApplicationController
  skip_onboarding_requirement

  def show
    return redirect_to(root_path) if Current.user.onboarded?

    case Current.user.onboarding_step
    when :workspace then redirect_to new_onboarding_workspace_path
    when :project   then redirect_to new_onboarding_project_path
    when :team      then redirect_to new_onboarding_team_path
    end
  end

  def update
    Current.user.update!(onboarded_at: Time.current) unless Current.user.onboarded?

    workspace = Current.user.onboarding_workspace
    if workspace && (project = workspace.projects.kept.first)
      redirect_to workspace_project_path(workspace, project), notice: t(".complete")
    elsif workspace
      redirect_to workspace_path(workspace), notice: t(".complete")
    else
      redirect_to root_path, notice: t(".complete")
    end
  end
end
