FactoryBot.define do
  factory :project do
    workspace
    name { Faker::App.name }
    created_by factory: :user

    # Production invariant (post-#660, pinned by #688): every project is born
    # with its creator's project_membership — Workspace#create_project writes
    # both in one transaction, so a membership-less project is a state the app
    # can no longer produce. And the creator is always a workspace member
    # (ProjectMembership validates it; create_project is only reachable by
    # members), so the factory ensures that too. Mirroring both keeps
    # ProjectPolicy specs on real states, not impossible ones.
    after(:create) do |project|
      unless project.workspace.memberships.kept.exists?(user: project.created_by)
        create(:membership, user: project.created_by, workspace: project.workspace)
      end
      unless project.project_memberships.exists?(user: project.created_by)
        project.project_memberships.create!(user: project.created_by, role: "creator")
      end
    end
  end
end
