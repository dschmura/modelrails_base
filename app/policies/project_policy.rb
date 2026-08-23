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

  # Intentionally narrower than the lifecycle actions: renaming is the
  # creator's call (identity), while archive/unarchive/destroy are governance
  # (workspace managers too) — see lifecycle_manageable?.
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

  # #687: any member could LIST every kept project while show? requires
  # project membership — rows most members could only bounce off. Members see
  # the projects they belong to; workspace managers (who already hold the
  # lifecycle powers above) see all. Reads Current.workspace the same way
  # ApplicationPolicy#membership does — the scope has no record to derive a
  # workspace from.
  class Scope < ApplicationPolicy::Scope
    def resolve
      if manager?
        scope.all
      else
        scope.joins(:project_memberships).where(project_memberships: { user_id: user.id })
      end
    end

    private

    def manager?
      Current.workspace&.memberships&.kept&.find_by(user: user)
        &.role&.permissions&.dig("manage_workspace") == true
    end
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
