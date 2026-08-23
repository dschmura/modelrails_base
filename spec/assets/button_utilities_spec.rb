require "rails_helper"

# Compiled-CSS probe (declaration-level, not selector-grep): proves the utility
# family actually compiles. .btn-secondary is the positive control — if IT is
# missing, the probe file/technique is wrong, not the code.
RSpec.describe "button utilities in compiled Tailwind" do
  let(:css) { Rails.root.join("app/assets/builds/tailwind.css").read }

  it "compiles .btn-secondary (positive control) and .btn-outline" do
    expect(css).to include(".btn-secondary")
    expect(css).to include(".btn-outline")
    expect(css.split(".btn-outline", 2).last[0, 600]).to include("--color-interactive")
  end
end
