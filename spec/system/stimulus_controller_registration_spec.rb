require "rails_helper"

# Controllers registered explicitly (rather than lazy-loaded from the
# "controllers" importmap prefix) have to be in the router BEFORE
# `lazyLoadControllersFrom` runs. stimulus-loading guards each autoload with
# `canRegisterController`, which is only false once an identifier is already
# registered — so registration order, not availability, decides whether the
# loader tries to import a path that does not exist and logs
# "Failed to autoload controller" (#1072).
#
# The controllers still work either way, which is exactly why this needs a
# spec: the failure is invisible to every other assertion in the suite and
# shows up only as red in a console nobody is watching.
RSpec.describe "Stimulus controller registration", type: :system do
  # console.error is patched before any application module evaluates, because
  # the autoload failures fire during page load. Every `visit` already waits
  # for controllers to connect (spec/support/stimulus_ready.rb), so by the time
  # an example asserts, the loader has run.
  CONSOLE_CAPTURE_JS = <<~JS
    window.__consoleErrors = [];
    const originalConsoleError = console.error;
    console.error = (...args) => {
      try { window.__consoleErrors.push(args.map(String).join(" ")) } catch (_) {}
      originalConsoleError.apply(console, args);
    };
  JS

  def console_errors
    page.evaluate_script("window.__consoleErrors || []")
  end

  before { cdp_add_init_script(CONSOLE_CAPTURE_JS) }

  it "logs no console error on the signed-out landing page" do
    visit "/"

    expect(console_errors).to be_empty
  end

  it "logs no console error on the docs index" do
    visit "/docs"

    expect(console_errors).to be_empty
  end
end
