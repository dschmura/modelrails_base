require "rails_helper"

RSpec.describe "Membership last_accessed_at touch", type: :system, js: true do
  let(:user) { create(:user) }
  let(:workspace_a) { create(:workspace, name: "Alpha") }
  let(:workspace_b) { create(:workspace, name: "Beta") }
  let!(:membership_a) { create(:membership, :owner, user: user, workspace: workspace_a) }
  let!(:membership_b) { create(:membership, :owner, user: user, workspace: workspace_b) }

  before do
    sign_in_via_form(user)
  end

  it "touches the membership on every workspace-scoped page visit" do
    expect(membership_a.last_accessed_at).to be_nil
    expect(membership_b.last_accessed_at).to be_nil

    visit workspace_path(workspace_a)
    expect(membership_a.reload.last_accessed_at).to be_within(5.seconds).of(Time.current)
    expect(membership_b.reload.last_accessed_at).to be_nil

    a_at_first_visit = membership_a.last_accessed_at
    travel 2.seconds

    visit workspace_path(workspace_b)
    expect(membership_a.reload.last_accessed_at).to eq(a_at_first_visit)
    expect(membership_b.reload.last_accessed_at).to be_within(5.seconds).of(Time.current)
  end
end
