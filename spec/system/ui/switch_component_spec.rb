# frozen_string_literal: true

require "rails_helper"

# ENHANCED preview-host proof for the switch component.
#
# The switch is a visually-hidden `<input type=checkbox role=switch class="peer sr-only">`
# (the `peer`) followed by two LATER-SIBLING spans inside a wrapper: the TRACK and
# the THUMB. The on/off visual is driven ENTIRELY by Tailwind's peer-* sibling
# cascade:
#
#   TRACK: bg-surface-sunken  ->  peer-checked:bg-interactive
#   THUMB: translate-x-0      ->  peer-checked:translate-x-[calc(100%-2px)]
#   TRACK focus ring:             peer-focus-visible:ring-[3px] ...
#
# The render harness only verifies class STRINGS are present — it cannot see
# whether `.peer:checked ~ .track` actually matches and recomputes the cascade.
# A broken DOM order (input not a peer, or track/thumb not later siblings) would
# pass the render harness but render a dead switch. This spec proves the cascade
# in a real browser by reading COMPUTED styles on vs off.
#
# Stable selectors (no component edit needed — see CRITICAL note below):
#   input: input[role="switch"]
#   TRACK: input[role="switch"] + span        (the input's immediate next sibling)
#   THUMB: span[aria-hidden="true"]           (the only aria-hidden span in the widget)
#
# CRITICAL: I did NOT edit the vendored switch component. The track/thumb have no
# data-* hooks, but their DOM position (input's next sibling; the aria-hidden span)
# is stable and load-bearing to the peer-* contract itself, so it is a legitimate
# selector. Adding a data attr would have meant changing the gem template too.
RSpec.describe "Switch component accessibility and visual transition", type: :system do
  PREVIEW = "/rails/view_components/ui/switch_component"

  TRACK_SELECTOR = 'input[role="switch"] + span'
  THUMB_SELECTOR = 'span[aria-hidden="true"]'

  # Read computed styles for the track + thumb off the live Playwright page.
  # `pw.evaluate` returns a Hash with STRING keys; symbolize at the boundary so
  # the rest of the spec reads cleanly.
  def computed_switch_styles
    raw = Capybara.current_session.driver.with_playwright_page do |pw|
      pw.evaluate(<<~JS)
        (() => {
          const track = document.querySelector(#{TRACK_SELECTOR.to_json});
          const thumb = document.querySelector(#{THUMB_SELECTOR.to_json});
          const ts = track ? getComputedStyle(track) : null;
          const hs = thumb ? getComputedStyle(thumb) : null;
          return {
            trackFound: !!track,
            thumbFound: !!thumb,
            trackBg: ts ? ts.backgroundColor : null,
            // Tailwind 4 implements `translate-x-*` via the native CSS `translate`
            // property (not the legacy `transform: translateX()`), so the thumb's
            // movement shows up here, while computed `transform` stays "none".
            thumbTranslate: hs ? hs.translate : null,
            thumbTransform: hs ? hs.transform : null
          };
        })()
      JS
    end
    raw.transform_keys(&:to_sym)
  end

  describe "AAA accessibility" do
    it "off scenario has role=switch and passes AAA in both themes" do
      visit "#{PREVIEW}/off"
      expect(page).to have_css('input[role="switch"]')

      # Scope to the whole switch widget (the outer label wraps input+track+thumb
      # and the text label). No color-contrast exclude — a real failure on the
      # interactive track/thumb colors would fail here.
      scope = [ "label" ]
      expect(axe_clean_in_both_themes?(include: scope)).to(
        be(true),
        axe_violations_in_both_themes(include: scope).join("\n")
      )
    end

    it "on scenario has role=switch and passes AAA in both themes" do
      visit "#{PREVIEW}/on"
      expect(page).to have_css('input[role="switch"]')

      scope = [ "label" ]
      expect(axe_clean_in_both_themes?(include: scope)).to(
        be(true),
        axe_violations_in_both_themes(include: scope).join("\n")
      )
    end
  end

  # Proves peer-checked:bg-interactive AND peer-checked:translate-x actually apply
  # — the cascade fix invisible to the render harness. If on and off compute the
  # same track background OR the same thumb translate, the cascade is dead and
  # this fails (do NOT fudge).
  describe "on/off visual transition (peer-checked cascade)" do
    it "track background-color and thumb translate DIFFER on vs off" do
      visit "#{PREVIEW}/off"
      expect(page).to have_css('input[role="switch"]')
      off = computed_switch_styles
      expect(off[:trackFound]).to be(true), "track span not found via #{TRACK_SELECTOR}"
      expect(off[:thumbFound]).to be(true), "thumb span not found via #{THUMB_SELECTOR}"

      visit "#{PREVIEW}/on"
      expect(page).to have_css('input[role="switch"]:checked')
      on = computed_switch_styles
      expect(on[:trackFound]).to be(true)
      expect(on[:thumbFound]).to be(true)

      # peer-checked:bg-interactive — the track recolors when checked.
      expect(on[:trackBg]).not_to(
        eq(off[:trackBg]),
        "track background did not change off->on (cascade broken). " \
        "off=#{off[:trackBg].inspect} on=#{on[:trackBg].inspect}"
      )

      # peer-checked:translate-x-[calc(100%-2px)] — the thumb slides when checked.
      # TW4 routes this through the CSS `translate` property; off resolves to a
      # zero offset and on to `calc(100% - 2px)`, so the two must differ.
      expect(on[:thumbTranslate]).not_to(
        eq(off[:thumbTranslate]),
        "thumb translate did not change off->on (cascade broken). " \
        "off=#{off[:thumbTranslate].inspect} on=#{on[:thumbTranslate].inspect}"
      )
      expect(on[:thumbTranslate]).to(
        include("100%"),
        "checked thumb translate should resolve the calc(100%-2px) offset; got #{on[:thumbTranslate].inspect}"
      )
    end
  end

  # Proves peer-focus-visible:ring-[3px] + peer-focus-visible:ring-interactive-focus
  # apply. The input is `sr-only` but focusable; the visible focus indicator lives
  # on the TRACK via the peer-focus-visible cascade.
  #
  # Approach: programmatic `.focus()` does not reliably trigger `:focus-visible` in
  # Chromium, so we ask for keyboard-originated focus (`focus({ focusVisible: true })`)
  # and fall back to simulating the keyboard modality so the heuristic latches.
  #
  # We assert on Tailwind 4's `--tw-ring-shadow` custom property rather than the
  # composed `box-shadow` shorthand: TW4 builds the ring from `--tw-ring-shadow`,
  # and `getComputedStyle().boxShadow` only weakly reflects it (a zero-size layer)
  # until paint, whereas the custom property is the load-bearing source of truth —
  # it resolves to the full `0 0 0 3px <color>` ring exactly when focus-visible is on.
  describe "focus-visible ring (peer-focus-visible cascade)" do
    it "renders a 3px focus ring on the track when the switch input is keyboard-focused" do
      visit "#{PREVIEW}/off"
      expect(page).to have_css('input[role="switch"]')

      unfocused_ring = track_ring_shadow

      ring = Capybara.current_session.driver.with_playwright_page do |pw|
        pw.evaluate(<<~JS)
          (() => {
            const input = document.querySelector('input[role="switch"]');
            // Focus from keyboard intent so :focus-visible matches (programmatic
            // .focus() is ambiguous for the heuristic). focusVisible:true asks the
            // engine to treat this as keyboard-originated focus.
            input.focus({ focusVisible: true });
            // Fallback for engines that ignore focusVisible: simulate the keyboard
            // modality so the :focus-visible heuristic latches.
            if (!input.matches(":focus-visible")) {
              input.blur();
              input.dispatchEvent(new KeyboardEvent("keydown", { key: "Tab", bubbles: true }));
              input.focus();
            }
            document.body.offsetHeight; // force reflow before reading
            const track = document.querySelector(#{TRACK_SELECTOR.to_json});
            const cs = getComputedStyle(track);
            return {
              focusVisible: input.matches(":focus-visible"),
              focused: document.activeElement === input,
              ringShadow: cs.getPropertyValue("--tw-ring-shadow").trim(),
              ringColor: cs.getPropertyValue("--tw-ring-color").trim()
            };
          })()
        JS
      end

      expect(ring["focused"]).to be(true), "switch input did not receive focus"
      expect(ring["focusVisible"]).to(
        be(true),
        "the engine did not latch :focus-visible for the focused switch input, " \
        "so the peer-focus-visible cascade cannot be exercised here"
      )

      # Unfocused: TW4's ring var is the inert `0 0 #0000` (no ring).
      expect(unfocused_ring).to match(/#0000\z/),
        "expected no ring when unfocused, got #{unfocused_ring.inspect}"

      # Focus-visible: the ring var resolves to a real 3px ring in the interactive
      # focus color. This is the actual proof peer-focus-visible:ring-[3px] applies.
      expect(ring["ringShadow"]).not_to(
        eq(unfocused_ring),
        "track ring did not change on focus-visible — peer-focus-visible:ring did not apply. " \
        "unfocused=#{unfocused_ring.inspect} focused=#{ring["ringShadow"].inspect}"
      )
      expect(ring["ringShadow"]).to(
        include("3px"),
        "focused ring should be the 3px ring; got #{ring["ringShadow"].inspect}"
      )
      expect(ring["ringColor"]).not_to(
        be_empty,
        "peer-focus-visible:ring-interactive-focus should set --tw-ring-color on focus"
      )
    end
  end

  # Reads the track's TW4 ring custom property off the live page.
  def track_ring_shadow
    Capybara.current_session.driver.with_playwright_page do |pw|
      pw.evaluate(<<~JS)
        getComputedStyle(document.querySelector(#{TRACK_SELECTOR.to_json}))
          .getPropertyValue("--tw-ring-shadow").trim()
      JS
    end
  end
end
