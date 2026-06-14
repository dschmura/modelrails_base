require "rails_helper"

# Verifies the SQLite durability/concurrency pragmas the template relies on are
# actually applied at runtime — not just declared in config/database.yml.
# Issue #304 (Nate Berkopec, fork-readiness panel): "verify on the deployed box
# that PRAGMA journal_mode is wal." We can't reach the deployed box from CI, but
# the test connection uses the same `default` config block, so asserting the
# live pragmas here is the repeatable, fork-inherited version of that check.
RSpec.describe "SQLite runtime pragmas" do
  def pragma(name)
    ActiveRecord::Base.connection.execute("PRAGMA #{name}").first.values.first
  end

  it "runs in WAL journal mode (readers don't block the single writer)" do
    expect(pragma("journal_mode")).to eq("wal")
  end

  it "keeps Rails' tuned safe defaults (synchronous NORMAL, foreign keys enforced)" do
    expect(pragma("synchronous")).to eq(1)  # 1 = NORMAL
    expect(pragma("foreign_keys")).to eq(1) # enforced
  end

  # `PRAGMA busy_timeout` reads 0 even though database.yml sets `timeout: 5000`.
  # Rails 8.1 installs a Ruby-level busy handler via the sqlite3 gem
  # (busy_handler_timeout=), which does NOT set the busy_timeout PRAGMA — the 5s
  # writer wait is active regardless. This test pins that surprising-but-correct
  # state so a future reader checking the live pragma isn't tempted to "fix" it:
  # adding `pragmas: { busy_timeout: ... }` would REPLACE Rails' busy handler.
  it "protects writers via a Ruby busy handler, so PRAGMA busy_timeout reads 0 by design" do
    expect(pragma("busy_timeout")).to eq(0)
    expect(ActiveRecord::Base.connection_db_config.configuration_hash[:timeout]).to eq(5000)
  end
end
