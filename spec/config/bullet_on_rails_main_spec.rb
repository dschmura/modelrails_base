require "rails_helper"

RSpec.describe "Bullet on Rails main" do
  it "runs in the test suite with its Active Record patches loaded" do
    expect(Bullet.enable?).to be(true)
    expect(Bullet::ActiveRecord).to be_a(Module)
  end

  it "catches an N+1 query on this Active Record" do
    create_list(:project, 2)
    # Bullet exempts records created in the current request; a new one separates setup from the read.
    Bullet.end_request
    Bullet.start_request
    Project.all.each { |project| project.workspace.name }

    expect(Bullet.notification?).to be(true)
  ensure
    Bullet.end_request
    Bullet.start_request
  end

  it "is still needed: Bullet does not know this Active Record by itself" do
    expect(Bullet::Dependency.method_defined?(:active_record82?)).to be(false),
      "Bullet now supports Active Record 8.2: delete config/bullet_on_rails_main.rb and its require in " \
      "config/application.rb, drop `require: false` from the Gemfile's bullet line, delete this file (#1337)"
  end
end
