# frozen_string_literal: true

# Stimulus boot lags behind page load, so an event dispatched before a
# controller connects is silently dropped — under random spec ordering an
# interactive preview spec can be the first to hit a cold module cache, an
# intermittent failure (#525 was exactly the gate not yet covering
# /draft_harness). This waits once, centrally, after any visit to a gated
# path; window.Stimulus is exposed in
# app/javascript/controllers/application.js. See /docs/developer/testing.
module StimulusReady
  GATED_PATHS = [ "/rails/view_components/", "/draft_harness" ].freeze

  def visit(path, *args, **kwargs)
    super.tap do
      wait_for_stimulus_controllers if GATED_PATHS.any? { |gated| path.to_s.include?(gated) }
    end
  end

  # Raises rather than returning false. A synchronization barrier that times
  # out silently is indistinguishable from one that succeeded, and the caller
  # below discards the return value — so before this, an exhausted wait and a
  # satisfied one looked identical (panel audit, 2026-08-26). The message names
  # the identifiers still unconnected, because with lazyLoadControllersFrom
  # "not connected" covers both "module still fetching" and "identifier will
  # never register" (a typo'd data-controller), and only the list distinguishes
  # them.
  def wait_for_stimulus_controllers(attempts: 25, interval: 0.1)
    attempts.times do
      return true if all_stimulus_controllers_connected?

      sleep interval
    end

    raise "Stimulus controllers never connected after #{(attempts * interval).round(1)}s: " \
          "#{unconnected_stimulus_identifiers.join(", ")} (page: #{page.current_path})"
  end

  private

  def all_stimulus_controllers_connected?
    page.evaluate_script(<<~JS)
      (function () {
        if (!window.Stimulus) return false;
        var els = document.querySelectorAll('[data-controller]');
        for (var i = 0; i < els.length; i++) {
          var ids = els[i].getAttribute('data-controller').split(/\\s+/);
          for (var j = 0; j < ids.length; j++) {
            if (ids[j] === '') continue;
            if (!window.Stimulus.getControllerForElementAndIdentifier(els[i], ids[j])) return false;
          }
        }
        return true;
      })()
    JS
  rescue StandardError
    # Mid-navigation or not-yet-evaluable: NOT connected, so keep waiting.
    # This used to return `true` — reporting "everything is connected" for any
    # evaluate_script hiccup, which is exactly what a contended runner
    # produces. The barrier was most likely to lie precisely when it mattered.
    false
  end

  def unconnected_stimulus_identifiers
    page.evaluate_script(<<~JS) || []
      (function () {
        if (!window.Stimulus) return ["(window.Stimulus absent)"];
        var out = [], els = document.querySelectorAll('[data-controller]');
        for (var i = 0; i < els.length; i++) {
          var ids = els[i].getAttribute('data-controller').split(/\\s+/);
          for (var j = 0; j < ids.length; j++) {
            if (ids[j] === '') continue;
            if (!window.Stimulus.getControllerForElementAndIdentifier(els[i], ids[j])) out.push(ids[j]);
          }
        }
        return out;
      })()
    JS
  rescue StandardError
    [ "(could not query the page)" ]
  end
end

RSpec.configure do |config|
  config.prepend StimulusReady, type: :system
end
