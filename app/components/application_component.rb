# frozen_string_literal: true

require "tailwind_merge"

# Base class for modelrails_ui components.
#
# The `cn` class-merge helper is backed by `tailwind_merge` (a small pure-Ruby
# runtime dependency) so a per-instance `class:` passthrough correctly OVERRIDES
# conflicting base utilities — e.g. `class: "rounded-full"` beats a base
# `rounded-md`, instead of both being emitted and CSS source-order deciding the
# winner. The install generator adds `gem "tailwind_merge"` to your Gemfile.
class ApplicationComponent < ViewComponent::Base
  private

  # Merge Tailwind class lists into one string, dropping nils/blanks and letting
  # later (passthrough) utilities win conflicts via tailwind_merge.
  #
  # tailwind_merge 1.x builds its internal LruRedux::Cache (NOT the thread-safe
  # variant), so a single shared Merger is not concurrency-safe under Puma.
  # We keep one Merger per thread: each thread owns its cache, so there is no
  # shared mutable state and no lock on this hot path.
  def cn(*classes)
    joined = classes.flatten.compact.reject { |c| c.to_s.empty? }.join(" ")
    (Thread.current[:modelrails_ui_tw_merge] ||= TailwindMerge::Merger.new).merge(joined)
  end
end
