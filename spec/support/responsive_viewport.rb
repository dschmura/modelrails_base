# frozen_string_literal: true

# Viewport-scoped system-spec helper for the responsive regression lane.
# Cuprite resizes the real browser window; always restore the suite default
# so later specs in the same process see the standard viewport.
module ResponsiveViewport
  def with_viewport(width, height = 900)
    page.driver.resize(width, height)
    yield
  ensure
    page.driver.resize(*CUPRITE_SCREEN_SIZE)
  end
end

RSpec.configure do |config|
  config.include ResponsiveViewport, type: :system
end
