require "rails_helper"

RSpec.describe "Operations operatorships", type: :request do
  let(:operator) { create(:user, first_name: "Opal", last_name: "Operator").tap { |u| Operatorship.grant!(user: u) } }

  before { sign_in(operator) }

  it "lists kept operators with who granted them" do
    granter = create(:user, first_name: "Gil", last_name: "Granter")
    second = create(:user, first_name: "Sam", last_name: "Second")
    Operatorship.grant!(user: second, granted_by: granter)

    get operations_operatorships_path
    html = Capybara.string(response.body)
    expect(html).to have_text("Opal Operator")
    expect(html).to have_text("Sam Second")
    expect(html).to have_text("Gil Granter")
  end

  # Fix round 2, item 9: `l(operatorship.created_at.to_date)` is a bare date
  # string — no machine-readable value, no timezone, grant time discarded.
  # activity_logs/_activity_log.html.erb (one directory over) already uses
  # <time datetime="...iso8601"> for the same kind of timestamp.
  it "renders the grant date in a machine-readable <time> element" do
    operatorship = Operatorship.kept.find_by!(user: operator)

    get operations_operatorships_path
    html = Capybara.string(response.body)
    expect(html).to have_css("time[datetime=\"#{operatorship.created_at.iso8601}\"]")
  end
end
