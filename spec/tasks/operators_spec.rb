require "rails_helper"
require "rake"

RSpec.describe "operators rake tasks" do
  before(:all) { Rails.application.load_tasks }

  def run_task(name, *args)
    Rake::Task[name].reenable
    Rake::Task[name].invoke(*args)
  end

  describe "operators:grant" do
    it "grants an operatorship with no granter and writes the audit row" do
      user = create(:user)

      expect { run_task("operators:grant", user.email_address) }
        .to change { user.reload.operator? }.from(false).to(true)
        .and change { ActivityLog.where(action: "operatorship.granted").count }.by(1)
    end

    it "is idempotent for an existing operator" do
      user = create(:user)
      Operatorship.grant!(user: user)

      expect { run_task("operators:grant", user.email_address) }.not_to change(Operatorship, :count)
    end

    it "aborts on an unknown email" do
      expect { run_task("operators:grant", "nobody@example.com") }.to raise_error(SystemExit)
    end
  end

  describe "operators:revoke" do
    it "revokes and writes the audit row" do
      user = create(:user)
      Operatorship.grant!(user: user)

      expect { run_task("operators:revoke", user.email_address) }
        .to change { user.reload.operator? }.from(true).to(false)
        .and change { ActivityLog.where(action: "operatorship.revoked").count }.by(1)
    end
  end

  describe "operators:list" do
    it "prints each kept operator's email" do
      user = create(:user)
      Operatorship.grant!(user: user)

      expect { run_task("operators:list") }.to output(/#{Regexp.escape(user.email_address)}/).to_stdout
    end
  end
end
