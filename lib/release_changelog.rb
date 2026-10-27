# frozen_string_literal: true

# The changelog and release-name convention bin/release reads through this module's public methods.
# A fork that keeps its changelog another way replaces this file and keeps their signatures.
module ReleaseChangelog
  class Error < StandardError; end

  NAME = '\d{4}\.\d{2}\.\d{2}(?:-\d+)?'
  UNRELEASED = "## [Unreleased]\n"

  module_function

  def names(today)
    date = today.strftime("%Y.%m.%d")
    (1..).lazy.map { |n| n == 1 ? date : "#{date}-#{n}" }
  end

  def name_release(text, name)
    head, rest = text.split(UNRELEASED, 2)
    raise Error, "CHANGELOG.md has no #{UNRELEASED.strip} section" if rest.nil?

    body, tail = rest.split(/^(?=## )/, 2)
    sections = fold(body)
    raise Error, "#{UNRELEASED.strip} has nothing in it; there is nothing to release" if sections.empty?

    released = sections.map { |title, lines| "### #{title}\n\n#{lines.join("\n")}\n" }.join("\n")
    "#{head}#{UNRELEASED}\n## v#{name}\n\n#{released}\n#{tail}"
  end

  def named_release(text)
    text[/^## \[Unreleased\]\n.*?^## v(#{NAME})$/m, 1]
  end

  def section(text, name)
    text[/^## v#{Regexp.escape(name)}\n(.*?)(?=^## |\z)/m, 1]&.strip
  end

  def fold(body)
    current = "Changed"
    body.lines(chomp: true).each_with_object({}) do |line, sections|
      if (title = line[/\A### (.+)/, 1])
        current = title
      elsif !line.strip.empty?
        (sections[current] ||= []) << line
      end
    end
  end
  private_class_method :fold
end
