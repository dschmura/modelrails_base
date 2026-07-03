class ProjectPolicy < ApplicationPolicy
  def index?
    membership.present?
  end

  def show?
    project_member?
  end

  def create?
    membership.present?
  end

  def update?
    project_membership&.creator?
  end

  def archive?
    lifecycle_manageable?
  end

  def unarchive?
    lifecycle_manageable?
  end

  def destroy?
    lifecycle_manageable?
  end

  private

  def lifecycle_manageable?
    project_membership&.creator? || can?("manage_workspace")
  end

  def project_membership
    @project_membership ||= record.project_memberships.find_by(user: user)
  end

  def project_member?
    project_membership.present?
  end
end
