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
  it "labels every action either activity feed can render" do
    Rails.application.eager_load!
    trackable = ApplicationRecord.descendants.select { |model| model.include?(Trackable) }
    actions = trackable.flat_map { |model| %w[created updated].map { |verb| "#{model.model_name.param_key}.#{verb}" } }
    actions += %w[membership.deactivated membership.reactivated membership.left]
    # Enumerated from the constant, not text-scanned: SECURITY_ACTIONS already
    # names Operatorship's two direct-write actions.
    actions += ActivityLog::SECURITY_ACTIONS.grep(/\Aoperatorship\./)

    literal_call = /ActivityLog\.create!\(/
    action_value = /action:\s*["']([\w.]+)["']/

    SecurityEventWriters::ALLOWED.each_key do |relative|
      source = without_comments(File.read(Rails.root.join(relative)))
      position = 0
      while (match = literal_call.match(source, position))
        position = match.end(0)
        finish = balanced_end(source, match.end(0) - 1)
        next unless finish

        call_args = source[match.end(0)...(finish - 1)]
        found = call_args.match(action_value)
        actions << found[1] if found
      end
    end
    actions.uniq!

    missing = actions.reject { |action| I18n.exists?("activity.actions.#{action}") }

    expect(missing).to be_empty,
      "Feed actions without an activity.actions label:\n  #{missing.join("\n  ")}"
  end

  # The check must be able to fail.
  it "reports a member without a label" do
    expect(I18n.exists?("settings.sessions.activity.user.zz_unlabeled")).to be(false)
  end
end
