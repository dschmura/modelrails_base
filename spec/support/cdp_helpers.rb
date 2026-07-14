# Ferrum/CDP helpers — the pure-Ruby replacements for the Playwright-specific
# operations the system specs used via `page.driver.with_playwright_page`.
# Cuprite exposes the underlying Ferrum::Browser at `page.driver.browser`.
#
# Playwright → ferrum cheatsheet:
#   pw.evaluate(async IIFE returning X)  -> cdp_evaluate_async(js)   (js resolves via arguments[last])
#   pw.evaluate(sync JS, no return)      -> cdp_execute(js)
#   pw.evaluate(sync JS returning X)     -> cdp_evaluate(js)
#   pw.context.add_init_script(src)      -> cdp_add_init_script(src)  (call BEFORE visiting)
#   pw.keyboard.press(key)               -> cdp_press(key)
#   pw.mouse.click(x, y)                 -> cdp_click_at(x, y)
#   pw.context.clear_cookies             -> cdp_clear_cookies
#   pw.context.new_cdp_session(...).send_message(m, params:) -> cdp_command(m, **params)
module CdpHelpers
  def cdp_browser
    page.driver.browser
  end

  # Inject/run JS as a statement (no implicit `return`). Ferrum's `evaluate`
  # wraps the source in `function(){ return X }`, which breaks UMD bundles like
  # axe-core that self-assign to `window`; `execute` runs the raw statement.
  def cdp_execute(js)
    cdp_browser.execute(js)
  end

  # Evaluate JS and return its value (synchronous).
  def cdp_evaluate(js)
    cdp_browser.evaluate(js)
  end

  # Await an async expression. The JS must resolve by calling the LAST argument:
  # `...then(v => arguments[arguments.length - 1](v))`. Returns the resolved value.
  def cdp_evaluate_async(js, wait: 20)
    cdp_browser.evaluate_async(js, wait)
  end

  # Register a script that runs before page scripts on every SUBSEQUENT
  # navigation (Playwright's add_init_script). Call BEFORE `visit`.
  def cdp_add_init_script(source)
    cdp_command("Page.addScriptToEvaluateOnNewDocument", source: source)
  end

  # Press a single key: "Enter", "Tab", "Escape", "Space", "ArrowDown", " ", "a"…
  def cdp_press(key)
    key = key.to_s
    cdp_browser.keyboard.type(key == " " ? :Space : key.to_sym)
  end

  # Click at absolute viewport coordinates.
  def cdp_click_at(x, y)
    cdp_browser.mouse.click(x: x, y: y)
  end

  # Clear all cookies for the current browsing context.
  def cdp_clear_cookies
    cdp_browser.cookies.clear
  end

  # Send a raw CDP command to the current page (WebAuthn domain, etc.).
  def cdp_command(method, **params)
    cdp_browser.page.command(method, **params)
  end
end

RSpec.configure do |config|
  config.include CdpHelpers, type: :system
end
