#
# The only backend customization in the app, and the deviation is deliberate:
# a fork renames the product's nouns in config/vocabulary.local.yml, and every
# translation must see those names without every call site passing them. The
# prepend is on `translate`, not `interpolate` — the i18n gem skips
# interpolation entirely when a call carries no values, so a hook one level
# down never runs for the common case. Caller-supplied values are merged on
# top, so a call can still override a token, and a genuinely missing argument
# (%{workspace_name} with no name) still raises: the vocabulary never fills a
# key the caller owns because, after #1108, no caller key shares a name with
# a noun. See /docs/developer/i18n (Vocabulary) and #1109.
module VocabularyInterpolation
  def translate(locale, key, options = I18n::EMPTY_HASH)
    super(locale, key, Vocabulary.tokens.merge(options))
  end
end

I18n::Backend::Simple.prepend(VocabularyInterpolation)
