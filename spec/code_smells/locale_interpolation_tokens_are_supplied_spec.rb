require "rails_helper"

# The i18n gem skips interpolation when a call passes no values, so an unknown
# %{token} leaks raw to the user, and `check-consistent-interpolations` cannot
# see it — it compares locales, and there is one. This spec is that gate:
# every token in every value is a vocabulary token (supplied by the backend
# hook) or a caller argument this list knows about. Adding a caller argument
# means adding it here, with the call site that supplies it.
RSpec.describe "Code smell: every locale interpolation token is supplied" do
  caller_supplied = %w[
    accepter action added_user_name address app_name cap count current date
    decliner_email device email first_name from hours_remaining
    invitee_email inviter limit max member metric minutes mode name
    new_email new_role nickname os percent period phrase project_name
    provider relative role sent skipped summary time title to user_name
    workspace_name
  ]
  # ^ from Step 1's measurement, minus the eight vocabulary tokens, sorted.
  # Two of these are filled client-side, not by a Ruby caller: `count` in
  # form_draft.restored_other and `name` in identity_picker.js.color_announce
  # are supplied by JavaScript, not a translation call argument — something
  # still supplies them, so they belong on this list rather than the
  # vocabulary's.
  js_filled_keys = %w[form_draft.restored_other identity_picker.js.color_announce]

  def tokens_in(path)
    File.readlines(path).each_with_index.flat_map do |line, index|
      next [] if line.match?(/\A\s*#/)
      line.scan(/%\{([A-Za-z_]+)\}/).flatten.map { |token| [ token, "#{path.basename}:#{index + 1}" ] }
    end
  end

  it "knows where every %{token} comes from" do
    known = caller_supplied + Vocabulary.tokens.keys.map(&:to_s)
    unknown = Dir.glob(Rails.root.join("config/locales/en/*.yml"))
      .flat_map { |f| tokens_in(Pathname.new(f)) }
      .reject { |token, _| known.include?(token) }
      .map { |token, location| "#{location}  %{#{token}}" }

    expect(unknown).to be_empty,
      "Interpolation token(s) nobody supplies — a vocabulary token, or add the caller argument to this spec:\n  #{unknown.join("\n  ")}"
  end

  it "reports a planted unknown token" do
    Dir.mktmpdir do |dir|
      path = Pathname.new(dir).join("probe.en.yml")
      path.write(%(en:\n  probe: "Hello %{nobody}"\n))

      expect(tokens_in(path)).to contain_exactly([ "nobody", "probe.en.yml:2" ])
    end
  end

  # config/initializers/vocabulary.rb documents that a string carrying BOTH a
  # noun token and a JS-filled placeholder raises on a value-less call: the
  # hook sees the noun token, merges Vocabulary.tokens in, and the JS-filled
  # placeholder (%{count}, %{name}) is left missing (#1111). Walking the
  # public `translations` tree, not `I18n.t`, so checking this never itself
  # triggers the raise it guards against.
  def resolved_value(key)
    key.split(".").inject(I18n.backend.translations.fetch(:en)) { |node, part| node[part.to_sym] }
  end

  it "keeps a JS-filled key's value free of a vocabulary token" do
    vocabulary_pattern = /%\{(#{Vocabulary.tokens.keys.join("|")})\}/
    offenders = js_filled_keys.select { |key| resolved_value(key).to_s.match?(vocabulary_pattern) }

    expect(offenders).to be_empty,
      "JS-filled key(s) also carry a vocabulary token — a value-less call would raise (#1111): #{offenders.join(', ')}"
  end

  # A caller that passes `workspace:` or `project:` to a translation is naming
  # the noun's slot with a record's name — the homonym that rendered "Join
  # course" in a spike and doubled a project's name in this branch. Names are
  # %{workspace_name} / %{project_name}; the noun tokens are the backend's.
  def offending_calls_in(path)
    call = /(?:\bt|I18n\.t|translate)\((?:[^()]|\((?:[^()]|\([^()]*\))*\))*\)/m
    vocabulary_names = Vocabulary.tokens.keys.join("|")
    label = path.to_s.start_with?(Rails.root.to_s) ? path.relative_path_from(Rails.root) : path.basename
    File.read(path).scan(call).filter_map do |text|
      next unless text.match?(/\b(#{vocabulary_names}):\s/)
      "#{label}  #{text.lines.first.strip[0, 80]}"
    end
  end

  it "never lets a caller pass a vocabulary token name as a translation argument" do
    offenders = Dir.glob(Rails.root.join("app/**/*.{rb,erb}"))
      .map { |f| Pathname.new(f) }
      .flat_map { |p| offending_calls_in(p) }

    expect(offenders).to be_empty,
      "Translation calls passing a vocabulary token name — use workspace_name:/project_name: for a record's name:\n  #{offenders.join("\n  ")}"
  end

  it "reports a planted call that passes a vocabulary token name" do
    Dir.mktmpdir do |dir|
      path = Pathname.new(dir).join("probe.rb")
      path.write(%(t("invitations.join", workspace: workspace.name)\n))

      expect(offending_calls_in(path)).to contain_exactly(a_string_starting_with("probe.rb"))
    end
  end
end
