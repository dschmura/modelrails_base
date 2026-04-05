require "rails_helper"

RSpec.describe CheckGravatarJob, type: :job do
  let(:user) { create(:user) }

  it "updates has_gravatar to true when Gravatar exists" do
    allow(GravatarService).to receive(:check).with(user.email_address).and_return(true)
    described_class.perform_now(user)
    expect(user.reload.has_gravatar).to be true
  end

  it "updates has_gravatar to false when Gravatar does not exist" do
    user.update_columns(has_gravatar: true)
    allow(GravatarService).to receive(:check).with(user.email_address).and_return(false)
    described_class.perform_now(user)
    expect(user.reload.has_gravatar).to be false
  end

  it "does NOT change avatar_source" do
    user.update_columns(avatar_source: "initials")
    allow(GravatarService).to receive(:check).with(user.email_address).and_return(true)
    described_class.perform_now(user)
    expect(user.reload.avatar_source).to eq("initials")
  end
end
