require "rails_helper"

# ActivityLog#readonly? blocks instance-level rewrites, but relation-level
# writes (update_all/delete_all/destroy_all/upsert) and raw SQL skip that
# check entirely. This spec closes the bypass: audit history stays
# append-only in app code until a retention policy (#438) designs its
# explicit carve-out — which should be added to ALLOWED below, not disabled
# inline.
RSpec.describe "Code smell: activity log immutability" do
  # Locals, not constants: a constant here lands on Object, where another
  # spec file's same-named constant clobbers it whenever CI shards both into
  # one worker (the ALLOWED collision that broke CI on 2026-08-14).
  bypass_writes = /\b(?:ActivityLog|activity_logs)\b[^\n]*\.(?:update_all|delete_all|destroy_all|update_columns|upsert(?:_all)?)\b/

  # path => reason. Empty until the #438 retention job exists.
  allowed_bypasses = {}.freeze

  it "no app or lib code rewrites or deletes activity log rows" do
    offenders = Dir[Rails.root.join("{app,lib}/**/*.rb")].flat_map do |file|
      relative = Pathname(file).relative_path_from(Rails.root).to_s
      next [] if allowed_bypasses.key?(relative)

      File.readlines(file).each_with_index.filter_map do |line, i|
        "#{relative}:#{i + 1}: #{line.strip}" if line.match?(bypass_writes)
      end
    end

    expect(offenders).to be_empty,
      "The audit trail is append-only (best-effort to write, impossible to " \
      "rewrite — CLAUDE.md deviation #4). Relation-level writes found:\n  " \
      "#{offenders.join("\n  ")}\nA legitimate retention job belongs in " \
      "allowed_bypasses in this spec with its reason."
  end
end
