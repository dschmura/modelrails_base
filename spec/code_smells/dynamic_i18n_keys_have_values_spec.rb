require "rails_helper"

# Two labels are looked up by a dynamic key — `settings.sessions.activity.<action>`
# for every ActivityLog::SECURITY_ACTIONS member, and `authentication.providers.<key>`
# for every configured sign-in provider — and they used to carry inline defaults
# so a member without a label rendered humanized text. Neither i18n gate can see
# a dynamic key (the static one cannot read it, the runtime one only fires on a
# path a spec walks), so this spec is the gate: add the member, add its label, or
# this is red. See /docs/developer/i18n (No inline defaults).
RSpec.describe "Code smell: every dynamic i18n key has a value" do
  it "labels every security action on the account activity list" do
    missing = ActivityLog::SECURITY_ACTIONS.reject { |action| I18n.exists?("settings.sessions.activity.#{action}") }

    expect(missing).to be_empty,
      "Security actions without a settings.sessions.activity label:\n  #{missing.join("\n  ")}"
  end

  it "labels the os variant of every action whose writer records an os" do
    missing = ActivityLog::SECURITY_ACTIONS_WITH_OS.reject do |action|
      I18n.exists?("settings.sessions.activity.#{action}_with_os")
    end

    expect(missing).to be_empty,
      "OS-labeled actions without a _with_os label:\n  #{missing.join("\n  ")}"
  end

  it "labels every sign-in provider, the email one included" do
    # Registry keys are OmniAuth strategy names; the stored provider is the normalized one.
    providers = Rails.application.config.x.oauth_providers.keys.map { |key| OmniauthAdapters.normalize_provider(key.to_s) } + [ "email" ]
    missing = providers.reject { |provider| I18n.exists?("authentication.providers.#{provider}") }

    expect(missing).to be_empty,
      "Providers without an authentication.providers label:\n  #{missing.join("\n  ")}"
  end

  # Both activity feeds (the workspace feed and this arc's cross-workspace
  # operations feed) render `activity.actions.<display_action>`. Trackable
  # writes <param_key>.created/updated for every includer, and
  # ActivityLog#display_action derives three membership variants from
  # metadata — that half is enumerable from the model layer.
  #
  # The remainder bypasses Trackable and writes a literal `action:` directly
  # (fix round 2, item 3). Rebuilt in fix round 3, item 1 / R26: a regex
  # scanning app/ for that shape is paren-fragile — ANY `)` between
  # `ActivityLog.create!(` and `action:` blinds it, and
  # application_controller.rb's own call was one argument swap away from
  # doing exactly that. Rather than guess at source shape, this scans only
  # SecurityEventWriters::ALLOWED (spec/support/security_event_writers.rb) —
  # the SAME reviewed list security_events_route_through_writer_spec.rb uses
  # to prove no OTHER file bypasses Trackable — with balanced_end so a nested
  # `)` inside the call can't hide `action:`, and without_comments so prose
  # merely naming the shape (trackable.rb's own header) can't forge a
  # phantom action. A new bypass writer must be added to that list before
  # either guard can see it.
  #
  # Fix round 4, item 2: this text scan cannot evaluate every Ruby shape, and
  # four of them (create without a bang, create! without parens, a non-literal
  # action value, a string-embedded paren that desyncs balanced_end) used to
  # make it skip SILENTLY — a missing label ships unnoticed. Now any write
  # shape it cannot resolve to a plain string literal fails loud, naming the
  # file and line, instead of passing. The one legitimate non-literal is
  # Trackable#create_activity's own `action: action` — it forwards its
  # caller's action rather than hardcoding one, and that whole family is
  # already enumerated above from the model descendants loop, so it is
  # declared safe by exact value below rather than silently allowed.
  # Shared with the scan below so the two can't drift apart. `\b` anchors the
  # left edge: without it, "transaction:" or "redaction:" — any kwarg whose
  # name merely ENDS in "action:" — matches before the real action: does.
  def action_arg_pattern
    /\baction:\s*(.+?)\s*(?:,|\z)/m
  end

  describe "the action: extraction regex" do
    it "is not fooled by a preceding kwarg ending in \"action:\"" do
      call_args = %(transaction: true, action: "workspace.updated")
      expect(call_args.match(action_arg_pattern)[1]).to eq('"workspace.updated"')
    end

    it "does not match a kwarg ending in \"action:\" when no real action: is present" do
      call_args = %(redaction: "a.b")
      expect(call_args.match(action_arg_pattern)).to be_nil
    end
  end

  it "labels every action either activity feed can render" do
    Rails.application.eager_load!
    trackable = ApplicationRecord.descendants.select { |model| model.include?(Trackable) }
    actions = trackable.flat_map { |model| %w[created updated].map { |verb| "#{model.model_name.param_key}.#{verb}" } }
    actions += %w[membership.deactivated membership.reactivated membership.left]
    # Task 11: workspace.suspended/unsuspended are likewise derived by
    # display_action from workspace.updated's own changes metadata, never
    # written by a literal ActivityLog.create! — neither guard below can see
    # them any other way.
    actions += %w[workspace.suspended workspace.unsuspended]
    # Enumerated from the constant, not text-scanned: SECURITY_ACTIONS already
    # names Operatorship's two direct-write actions.
    actions += ActivityLog::SECURITY_ACTIONS.grep(/\Aoperatorship\./)

    # No trailing `\(` — a paren-less call (gap: no parens) must still be
    # found so it can be reported, not silently missed. `(?=[\s(]|\z)`
    # anchors the boundary instead of `\b`, which `!?` backtracks past a
    # literal "!" (verified: `\bcreate!?\b` matches "create" and leaves "!("
    # unconsumed).
    write_call = /\bActivityLog\.create!?(?=[\s(]|\z)/
    literal_value = /\A["']([\w.]+)["']\z/
    declared_dynamic = { "app/models/concerns/trackable.rb" => [ "action" ] }.freeze

    unresolved = []

    SecurityEventWriters::ALLOWED.each_key do |relative|
      source = without_comments(File.read(Rails.root.join(relative)))
      position = 0
      while (match = write_call.match(source, position))
        line = source[0...match.begin(0)].count("\n") + 1
        position = match.end(0)

        paren = source[position..].match(/\A[ \t]*\(/)
        unless paren
          unresolved << "#{relative}:#{line}: ActivityLog write with no parentheses"
          next
        end

        open_index = position + paren[0].length - 1
        finish = balanced_end(source, open_index)
        unless finish
          unresolved << "#{relative}:#{line}: ActivityLog write whose parentheses never balance " \
            "(a `(` inside a string literal desyncs the depth count)"
          next
        end
        position = finish

        call_args = source[(open_index + 1)...(finish - 1)]
        action_match = call_args.match(action_arg_pattern)
        unless action_match
          unresolved << "#{relative}:#{line}: ActivityLog write with no resolvable action: argument " \
            "(a `)` inside an earlier string literal may have truncated the argument list)"
          next
        end

        raw_value = action_match[1]
        literal = raw_value.match(literal_value)
        if literal
          actions << literal[1]
        elsif !declared_dynamic[relative]&.include?(raw_value)
          unresolved << "#{relative}:#{line}: ActivityLog action `#{raw_value}` is not a string literal"
        end
      end
    end
    actions.uniq!

    expect(unresolved).to be_empty,
      "This scan reads app/ as text and cannot evaluate a non-literal action; each of these calls must " \
      "either use a literal action: string or have its exact value added to declared_dynamic above:\n  " \
      "#{unresolved.join("\n  ")}"

    missing = actions.reject { |action| I18n.exists?("activity.actions.#{action}") }

    expect(missing).to be_empty,
      "Feed actions without an activity.actions label:\n  #{missing.join("\n  ")}"
  end

  # The check must be able to fail.
  it "reports a member without a label" do
    expect(I18n.exists?("settings.sessions.activity.user.zz_unlabeled")).to be(false)
  end
end
