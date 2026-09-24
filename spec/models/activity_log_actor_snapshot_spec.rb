require "rails_helper"

# An audit row outlives the people in it.
#
# `activity_logs.actor_id` carried a real FK to `users` with no cleanup path,
# so any user who had ever acted could not be destroyed. The natural fixes are
# both wrong: `dependent: :destroy` deletes history to delete a person, and
# `dependent: :nullify` rewrites immutable rows to hide who acted (the
# immutability guard fences that spelling for exactly this reason).
#
# So the row carries a SNAPSHOT of the actor's name, taken at write time, and
# the FK is gone. The historical fact stops depending on the user row still
# existing — which is what an audit table wants anyway (#1122).
RSpec.describe "ActivityLog actor snapshot" do
  let(:actor) { create(:user, first_name: "Dana", last_name: "Ruiz") }
  let(:workspace) { actor.workspaces.sole }

  def acting_as(user)
    Current.session = user.sessions.create!(user_agent: "spec", ip_address: "127.0.0.1")
    Current.workspace = user.workspaces.sole
    yield
  ensure
    Current.session = nil
    Current.workspace = nil
  end

  describe "at write time" do
    it "records the actor's name on the row" do
      log = acting_as(actor) { workspace.update!(name: "Renamed"); workspace.activities.last }

      expect(log.actor_name).to eq("Dana Ruiz")
    end

    it "leaves the snapshot blank when there is no actor" do
      log = ActivityLog.create!(action: "workspace.updated", trackable: workspace,
                                actor: nil, workspace: workspace)

      expect(log.actor_name).to be_nil
    end

    # The whole point of a snapshot: the row states what was true then.
    it "does not follow the actor's later rename" do
      log = acting_as(actor) { workspace.update!(name: "Renamed"); workspace.activities.last }

      actor.update!(first_name: "Dee", last_name: "Ruiz")

      expect(log.reload.display_subject).to eq("Dana Ruiz")
    end
  end

  describe "after the actor is gone" do
    it "no longer blocks the actor's destruction" do
      acting_as(actor) { workspace.update!(name: "Renamed") }
      expect(ActivityLog.where(actor_id: actor.id)).to be_any

      expect { actor.destroy! }.not_to raise_error
    end

    it "still names who acted" do
      log = acting_as(actor) { workspace.update!(name: "Renamed"); workspace.activities.last }
      actor.destroy!

      expect(log.reload.display_subject).to eq("Dana Ruiz")
    end

    # Rows written before the snapshot column existed have a dangling actor_id
    # and nothing to fall back to. "System" would be a lie -- a person did this
    # -- so those rows get their own neutral noun.
    it "distinguishes a departed actor from no actor at all" do
      orphan = ActivityLog.create!(action: "workspace.updated", trackable: workspace,
                                   actor: actor, workspace: workspace)
      # Raw SQL on purpose: ActivityLog#readonly? refuses update_columns, which
      # is the immutability guarantee doing its job. Nothing in the app may
      # blank this column -- only a row that predates it can be blank.
      ActiveRecord::Base.connection.execute(
        "UPDATE activity_logs SET actor_name = NULL WHERE id = #{orphan.id}"
      )
      actor.destroy!

      expect(orphan.reload.display_subject).to eq(I18n.t("activity.departed_actor"))
    end

    it "reports no subject at all when the row never had an actor" do
      log = ActivityLog.create!(action: "workspace.updated", trackable: workspace,
                                actor: nil, workspace: workspace)

      expect(log.display_subject).to be_nil
    end
  end

  # The other half of the ruling: both columns now fail the same way. Leaving
  # one with a FK and one without is the state that produced this issue.
  it "keeps actor_id and trackable_id consistently free of foreign keys" do
    fks = ActiveRecord::Base.connection.foreign_keys("activity_logs").map(&:column)

    expect(fks).not_to include("actor_id"),
      "actor_id regained a FK, so a departed actor blocks user deletion again (#1122)"
    expect(fks).not_to include("trackable_id"),
      "trackable_id is polymorphic and cannot carry a FK"
  end
end
