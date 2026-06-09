# frozen_string_literal: true

module UI
  # # Card title
  #
  # The heading inside a card. It is a real heading element so it participates in
  # the document outline — which means the CALLER owns its level. It defaults to
  # `<h3>` (a card usually sits under an `<h2>` section), but you MUST pass `level:`
  # whenever that default would skip or misorder the page's heading hierarchy.
  #
  # ## Accessibility contract
  # - **Guarantees:** renders a real `<h1>`–`<h6>` (never a styled `<div>`) using
  #   the `text-text-heading` token; an out-of-range `level:` fails loud in dev and
  #   falls back to `<h3>` in production rather than emitting invalid markup.
  # - **You supply:** the correct `level:` for where this card sits in the outline.
  LEVELS = (1..6).freeze
  DEFAULT_LEVEL = 3

  class CardTitleComponent < ApplicationComponent
    BASE = "text-text-heading leading-none font-semibold"

    def initialize(title = nil, level: DEFAULT_LEVEL, **html_attrs)
      @title = title || html_attrs.delete(:label) || html_attrs.delete(:title)
      @level = resolve_level(level)
      @extra_class = html_attrs.delete(:class)
      @html_attrs = html_attrs
    end

    def call
      content_tag(:"h#{@level}", content.presence || @title, class: cn(BASE, @extra_class), **@html_attrs)
    end

    private

    # Fail loud on an out-of-range level in development/test so a skipped/invalid
    # heading is caught immediately; fall back to <h3> in production so a bad level
    # never emits invalid markup. The Rails.respond_to?(:env) guard stays correct
    # even when the Rails module is defined but Rails.env isn't booted (the gem's
    # Rails-less tests load rails/generators, which defines Rails without Rails.env).
    def resolve_level(level)
      return level.to_i if LEVELS.include?(level.to_i)

      unless defined?(Rails) && Rails.respond_to?(:env) && Rails.env.production?
        raise ArgumentError,
          "UI::CardTitleComponent: level: must be 1-6, got #{level.inspect}."
      end

      DEFAULT_LEVEL
    end
  end
end
