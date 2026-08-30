require "rails_helper"

# config/initializers/filter_parameter_logging.rb feeds two surfaces at once:
# request-log parameter filtering and ActiveRecord's `filter_attributes`
# (Rails mirrors `config.filter_parameters` into it at boot). `#inspect` is
# the emergent behavior of that mirror, so it is what these examples assert —
# a personal-data attribute that prints in a console or an error report
# prints in the logs too.
RSpec.describe "personal-data parameters are filtered" do
  it "filters a user's name" do
    output = User.new(first_name: "Ada", last_name: "Lovelace").inspect

    expect(output).to include('first_name: [FILTERED]', 'last_name: [FILTERED]')
  end

  it "filters a client's company name" do
    expect(ClientAccess.new(company_name: "BigCo").inspect).to include('company_name: [FILTERED]')
  end

  it "filters the company name on a client invitation" do
    expect(Invitation.new(company_name: "BigCo").inspect).to include('company_name: [FILTERED]')
  end
end
