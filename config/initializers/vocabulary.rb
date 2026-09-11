#
# The only backend customization in the app, and the deviation is deliberate:
# a fork renames the product's nouns in config/vocabulary.local.yml, and every
# translation must see those names without every call site passing them. The
# prepend is on `translate`, not `interpolate` — the i18n gem skips
# interpolation entirely when a call carries no values, so a hook one level
# down never runs for the common case. The tokens are merged only into calls
# whose resolved string uses one: a value-less call for a string that keeps
# a %{count} or %{name} for client-side JavaScript must stay value-less, or
# the gem interpolates it and raises (#1111). Caller-supplied values are
# merged on top, so a call can still override a token, and a genuinely
# missing argument (%{workspace_name} with no name) still raises: after
# #1108 no caller key shares a name with a noun. See /docs/developer/i18n
# (Vocabulary) and #1109.
#
# vocabulary_token_pattern is memoized on first call, not built as a
# module-body constant: `Vocabulary` lives in app/lib and isn't yet
# resolvable while config/initializers/*.rb are loading (confirmed with
# `bin/rails runner` — a bare `Vocabulary.tokens` at this file's top level
# raises NameError; icons.rb's `after_initialize` wrapper around
# `IconRegistry.eager_load!` is this codebase's existing workaround for the
# same ordering issue). Deferring the reference to first call, after boot
# completes, keeps the pattern built exactly once without touching Vocabulary
# during initializer load.
module VocabularyInterpolation
  def translate(locale, key, options = I18n::EMPTY_HASH)
    return super unless uses_vocabulary?(lookup(locale, key, options[:scope], options))

    super(locale, key, Vocabulary.tokens.merge(options))
  end

  private

  def uses_vocabulary?(resolved)
    case resolved
    when String then resolved.match?(vocabulary_token_pattern)
    when Hash then resolved.values.any? { |value| uses_vocabulary?(value) }
    when Array then resolved.any? { |value| uses_vocabulary?(value) }
    else false
    end
  end

  def vocabulary_token_pattern
    @vocabulary_token_pattern ||= /%\{(#{Vocabulary.tokens.keys.join("|")})\}/
  end
end

I18n::Backend::Simple.prepend(VocabularyInterpolation)
