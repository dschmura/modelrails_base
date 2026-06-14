class ResourcePolicy < ApplicationPolicy
  def index?
    project_member?
  end

  def show?
    project_member?
  end

  def create?
    project_membership&.creator? || project_membership&.editor?
  end

  def update?
    resource_creator? || project_membership&.creator?
  end

  def destroy?
    resource_creator? || project_membership&.creator? || can?("manage_workspace")
  end

  def reposition?
    project_membership&.creator? || project_membership&.editor?
  end

  private

  def project_membership
    project = record.respond_to?(:project) ? record.project : Current.project
    @project_membership ||= project&.project_memberships&.find_by(user: user)
  end

  def project_member?
    project_membership.present?
  end

  def resource_creator?
    record.created_by == user
  end
end
