# frozen_string_literal: true

# The changelog convention bin/release relies on: cut, section and prepared_name.
# A fork with another convention replaces this file and keeps those three.
module ReleaseChangelog
  class Error < StandardError; end

  NAME = '\d{4}\.\d{2}\.\d{2}(?:-\d+)?'
  UNRELEASED = "## [Unreleased]\n"

  module_function

  def cut(text, name)
    head, rest = text.split(UNRELEASED, 2)
    raise Error, "CHANGELOG.md has no #{UNRELEASED.strip} section" if rest.nil?

    body, tail = rest.split(/^(?=## )/, 2)
    sections = fold(body)
    raise Error, "#{UNRELEASED.strip} has nothing in it; there is nothing to release" if sections.empty?

    released = sections.map { |title, lines| "### #{title}\n\n#{lines.join("\n")}\n" }.join("\n")
    "#{head}#{UNRELEASED}\n## v#{name}\n\n#{released}\n#{tail}"
  end

  def fold(body)
    current = nil
    body.lines(chomp: true).each_with_object({}) do |line, sections|
      if (title = line[/\A### (.+)/, 1])
        current = title
        sections[title] ||= []
      elsif !line.strip.empty?
        (sections[current || "Changed"] ||= []) << line
      end
    end
  end

  def section(text, name)
    text[/^## v#{Regexp.escape(name)}\n(.*?)(?=^## |\z)/m, 1]&.strip
  end

  def prepared_name(text)
    text[/^## \[Unreleased\]\n.*?^## v(#{NAME})$/m, 1]
  end
end
