# frozen_string_literal: true

require "rails_helper"

# `position: absolute`/`fixed` escapes overflow clipping but never a *stacking context*:
# a floating panel's `z-50` is scoped to the nearest positioned ancestor with a z-index.
# A `sticky z-40` header (app/views/shared/_header.html.erb) and a `backdrop-blur` navbar
# (UI::NavbarComponent) are both ordinary chrome here, and both establish one — so no
# z-index on the panel lifts it above a sibling in the root context.
#
# The fix is the top layer: `showPopover()` paints the panel above every stacking context
# while leaving it in the DOM, so the Stimulus actions inside it stay bound.
#
# The catch, and why only the anchor-positioned band is promoted: the top layer makes the
# *initial containing block* the containing block, so a panel placed with `absolute` +
# `top-full` offsets resolves against the viewport and lands off its trigger. Panels placed
# with CSS anchor positioning are already `position: fixed` against the viewport, so
# promotion changes paint order only.
RSpec.describe "Overlay stacking context", type: :system do
  # What a user actually cares about: is the panel clickable, or is something else painted
  # on top of it? `elementFromPoint` answers exactly that.
  def occluded?(selector)
    page.evaluate_script(<<~JS)
      (() => {
        const el = document.querySelector("#{selector}");
        const box = el.getBoundingClientRect();
        const hit = document.elementFromPoint(box.left + box.width / 2, box.top + box.height / 2);
        return !(hit === el || el.contains(hit));
      })()
    JS
  end

  def gap_below_trigger(panel, trigger)
    page.evaluate_script(<<~JS)
      (() => {
        const t = document.querySelector("#{trigger}").getBoundingClientRect();
        const p = document.querySelector("#{panel}").getBoundingClientRect();
        return Math.round(p.top - t.bottom);
      })()
    JS
  end

  describe "a dropdown menu placed by CSS anchor positioning" do
    let(:panel) { "[data-menu-target=menu]" }
    let(:trigger) { "[data-menu-target=trigger]" }

    before do
      visit "/rails/view_components/ui/dropdown_menu_component/inside_stacking_context"
      find(trigger).click
      expect(page).to have_css(panel)
    end

    it "keeps the panel above page content that outranks its stacking context" do
      expect(occluded?(panel)).to be(false)
    end

    # The half the top layer would silently destroy if the panel were placed with
    # `absolute` offsets instead of anchor positioning.
    it "still anchors the panel to its trigger" do
      expect(gap_below_trigger(panel, trigger)).to be_between(2, 8)
    end

    it "still sizes the panel from its own classes, not the UA popover box" do
      width = page.evaluate_script(%{Math.round(document.querySelector("#{panel}").getBoundingClientRect().width)})

      expect(width).to be_between(128, 400) # min-w-[8rem], shrink-wrapped to its items
    end
  end

  # Browsers that support the Popover API but NOT anchor positioning (Firefox, Safari at
  # time of writing) fall back to `absolute` + `top-full` offsets. Promoting THAT lands the
  # panel against the viewport instead of its trigger — measured at 1320px adrift. So the
  # guard is the invariant itself, not a feature name: promote only what is already
  # `position: fixed`, where the containing-block change is a no-op.
  describe "a panel on the pre-Baseline absolute fallback" do
    let(:panel) { "[data-menu-target=menu]" }
    let(:trigger) { "[data-menu-target=trigger]" }

    before do
      visit "/rails/view_components/ui/dropdown_menu_component/inside_stacking_context"
      # Emulate a browser without anchor positioning: the panel resolves to `absolute`.
      page.execute_script(<<~JS)
        const css = document.createElement("style");
        css.textContent = "[data-menu-target=menu] { position: absolute !important; top: 100% !important; left: 0 !important; }";
        document.head.appendChild(css);
      JS
      find(trigger).click
      expect(page).to have_css(panel)
    end

    it "is not promoted to the top layer" do
      promoted = page.evaluate_script(<<~JS)
        (() => { const el = document.querySelector("#{panel}");
                 try { return el.matches(":popover-open") } catch (e) { return false } })()
      JS

      expect(promoted).to be(false)
    end

    it "stays anchored to its trigger" do
      expect(gap_below_trigger(panel, trigger)).to be_between(0, 12)
    end
  end
end
