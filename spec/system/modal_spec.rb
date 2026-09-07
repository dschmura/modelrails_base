require "rails_helper"

RSpec.describe "Modal system", type: :system do
  before do
    visit root_path
    # Dismiss the cookie consent banner if present so it doesn't intercept pointer events
    page.execute_script(<<~JS)
      const banner = document.querySelector('[data-biscuit-target="banner"]');
      if (banner) banner.remove();
    JS
    # Set a fast animation duration on the root element (where the controller reads it from)
    page.execute_script("document.documentElement.style.setProperty('--modal-animation-duration', '50ms')")
  end

  def inject_test_modal(options = {})
    open_value = options[:open] ? 'data-modal-open-value="true"' : ""
    page.execute_script(<<~JS)
      const wrapper = document.createElement('div');
      wrapper.setAttribute('data-controller', 'modal');
      #{options[:open] ? "wrapper.setAttribute('data-modal-open-value', 'true');" : ""}
      wrapper.innerHTML = `
        <button data-action="click->modal#open" id="test-modal-trigger" style="min-width:44px;min-height:44px">Open Modal</button>
        <dialog data-modal-target="dialog" id="test-modal"
                role="dialog" aria-modal="true" aria-labelledby="test-modal-title"
                class="bg-transparent backdrop:bg-transparent p-4">
          <div data-modal-target="panel"
               style="opacity:0; transform:scale(0.95); background:white; padding:24px; border-radius:8px; min-width:300px;">
            <h2 id="test-modal-title">Test Modal</h2>
            <p>Modal content for testing</p>
            <button data-action="click->modal#close" id="test-modal-close" aria-label="Close dialog" style="min-width:44px;min-height:44px">Close</button>
            <a href="#" id="test-modal-link" style="display:inline-flex;min-width:44px;min-height:44px;align-items:center">A focusable link</a>
          </div>
        </dialog>
      `;
      document.body.appendChild(wrapper);
    JS
  end

  describe "opening" do
    it "opens when trigger button is clicked" do
      inject_test_modal
      click_button "Open Modal"
      expect(page).to have_css("dialog[open]")
      expect(page).to have_text("Test Modal")
    end

    it "opens on connect when open value is true" do
      inject_test_modal(open: true)
      expect(page).to have_css("dialog[open]")
      expect(page).to have_text("Test Modal")
    end
  end

  describe "closing" do
    before do
      inject_test_modal
      click_button "Open Modal"
      expect(page).to have_css("dialog[open]")
    end

    it "closes when close button is clicked" do
      click_button "Close"
      expect(page).to have_no_css("dialog[open]")
    end

    it "closes on Escape key" do
      cdp_press("Escape")
      expect(page).to have_no_css("dialog[open]")
    end

    it "closes on backdrop click" do
      cdp_click_at(5, 5)
      expect(page).to have_no_css("dialog[open]")
    end

    it "returns focus to trigger button after close" do
      click_button "Close"
      expect(page).to have_no_css("dialog[open]")
      focused_id = page.evaluate_script("document.activeElement?.id")
      expect(focused_id).to eq("test-modal-trigger")
    end
  end

  describe "accessibility" do
    before do
      inject_test_modal
      click_button "Open Modal"
      expect(page).to have_css("dialog[open]")
    end

    it "has role=dialog" do
      expect(page).to have_css("dialog[role='dialog']")
    end

    it "has aria-modal=true" do
      expect(page).to have_css("dialog[aria-modal='true']")
    end

    it "has aria-labelledby pointing to title" do
      expect(page).to have_css("dialog[aria-labelledby='test-modal-title']")
      expect(page).to have_css("h2#test-modal-title", text: "Test Modal")
    end

    it "close button is keyboard accessible" do
      # showModal() autofocuses the dialog's first focusable descendant (the
      # close button), so a raw Enter press exercises the native
      # focused-button activation path. Capybara's cross-driver `send_keys`
      # is NOT usable here: Cuprite's implementation performs a real mouse
      # click before typing (unlike Playwright's `press`), and that click
      # closes the dialog and restores focus to the trigger button BEFORE
      # the Enter keydown/keyup land — which then reopens the dialog via the
      # trigger's own native Enter-activates-focused-button behavior.
      find("#test-modal-close")
      cdp_press("Enter")
      expect(page).to have_no_css("dialog[open]")
    end
  end

  # #713 filed this as a live bug: Turbo's snapshot clone normalises only `select`,
  # `input[type=password]` and `noscript`, so a dialog left open when the user
  # navigates away should survive into the cached page and come back non-modal but
  # still carrying the hardcoded `aria-modal="true"` (UI::DialogComponent) — a named
  # dialog announced in DOM order, claiming the rest of the page is not there.
  # Measured on turbo-rails 2.0.23 it does not happen: Turbo defers `snapshot.clone()`
  # one event-loop tick past `turbo:before-cache`, and in that window the body is
  # replaced and `modal_controller#disconnect()` closes the dialog on the (now
  # detached) old body that the clone is taken from. Every dialog in this app is under
  # that controller, so the protection is `disconnect()` — incidental, and load-bearing.
  # This example pins it: drop the close from `disconnect()` and #713 fails here
  # instead of shipping. The closed dialog keeps its `aria-modal` attribute but is
  # `display: none`, so the assertion is deliberately visibility-scoped — nothing a
  # screen reader can reach may claim modality.
  describe "Turbo snapshot restore (#713)" do
    it "restores with no open dialog and nothing exposed claiming modality" do
      inject_test_modal
      click_button "Open Modal"
      expect(page).to have_css("dialog[open]")

      # A real Turbo link, clicked. `visit` is a hard browser goto: it fires no
      # `turbo:before-cache` and leaves the snapshot cache empty, so Back would
      # re-request the page and the restore under test never happens. The link goes
      # inside the panel because a modal dialog swallows every pointer event aimed
      # at the page behind it.
      page.execute_script(<<~JS)
        const link = document.createElement('a');
        link.id = 'test-modal-away';
        link.href = '#{page_path(:about)}';
        link.textContent = 'Leave via Turbo';
        link.setAttribute('style', 'display:inline-flex;min-width:44px;min-height:44px;align-items:center');
        document.querySelector('[data-modal-target="panel"]').appendChild(link);
      JS
      click_link "Leave via Turbo"
      expect(page).to have_current_path(page_path(:about))

      page.go_back

      expect(page).to have_current_path(root_path)
      expect(page).to have_css("#test-modal", visible: :all)
      expect(page).to have_no_css("dialog[open]")
      expect(page).to have_no_css('[aria-modal="true"]')
    end
  end

  describe "reduced motion" do
    it "skips animation when prefers-reduced-motion is set" do
      cdp_emulate_reduced_motion
      inject_test_modal
      click_button "Open Modal"
      expect(page).to have_css("dialog[open]")

      # Panel should be immediately visible (opacity 1, no transition)
      panel_opacity = page.evaluate_script(
        'document.querySelector("[data-modal-target=\\"panel\\"]")?.style.opacity'
      )
      expect(panel_opacity).to eq("1")
    end
  end
end
