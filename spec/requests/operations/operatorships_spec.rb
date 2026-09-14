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

  # Fix round 2, item 9 added the machine-readable <time datetime="...iso8601">
  # (activity_logs/_activity_log.html.erb, one directory over, already used
  # one). Fix round 3, item 2 / R27: round 2 also replaced the VISIBLE date
  # with time_ago_in_words, which round 1 never asked for — datetime is not
  # announced by screen readers or shown by browsers, so a roster whose whole
  # job is who-granted-what-when lost the date for every human and every AT
  # user. Both assertions matter: datetime alone would pass even with the
  # visible text reading "about 6 months ago".
  it "renders the grant date in a machine-readable <time> element, with the date visible as its content" do
    operatorship = Operatorship.kept.find_by!(user: operator)

    get operations_operatorships_path
    html = Capybara.string(response.body)
    expect(html).to have_css("time[datetime=\"#{operatorship.created_at.iso8601}\"]",
      text: I18n.l(operatorship.created_at.to_date))
  end
end
