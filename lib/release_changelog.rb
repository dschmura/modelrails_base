# frozen_string_literal: true

# The changelog, its changelog.d fragments, and the release-name convention bin/release reads through this module.
# A fork that keeps its changelog another way replaces this file and keeps their signatures.
module ReleaseChangelog
  class Error < StandardError; end

  NAME = '\d{4}\.\d{2}\.\d{2}(?:-\d+)?'
  UNRELEASED = "## [Unreleased]\n"
  FRAGMENTS = "changelog.d"

  module_function

  def names(today)
    date = today.strftime("%Y.%m.%d")
    (1..).lazy.map { |n| n == 1 ? date : "#{date}-#{n}" }
  end

  def name_release(text, name, fragments = [])
    head, rest = text.split(UNRELEASED, 2)
    raise Error, "CHANGELOG.md has no #{UNRELEASED.strip} section" if rest.nil?

    body, tail = rest.split(/^(?=## )/, 2)
    sections = fold([ body, *fragments ])
    raise Error, "no entries under #{UNRELEASED.strip} or in #{FRAGMENTS}/; there is nothing to release" if sections.empty?

    released = sections.map { |title, lines| "### #{title}\n\n#{lines.join("\n")}\n" }.join("\n")
    "#{head}#{UNRELEASED}\n## v#{name}\n\n#{released}\n#{tail}"
  end

  def fragment?(path) = path.match?(%r{\A#{FRAGMENTS}/[^/]+\.md\z}) && File.basename(path) != "README.md"
  def fragment(title, entries) = "### #{title}\n\n#{entries.join("\n")}\n"

  def named_release(text)
    text[/^## \[Unreleased\]\n.*?^## v(#{NAME})$/m, 1]
  end

  def unreleased(text, fragments = [])
    body = text.split(UNRELEASED, 2).last.to_s.split(/^(?=## )/, 2).first.to_s
    fold([ body, *fragments ]).values.flatten
  end

  def section(text, name)
    text[/^## v#{Regexp.escape(name)}\n(.*?)(?=^## |\z)/m, 1]&.strip
  end

  # tagged: each shipped release's name and the CHANGELOG.md it was tagged with.
  def changed_releases(text, tagged)
    tagged.filter_map do |name, at_tag|
      shipped, now = [ at_tag, text ].map { |t| section(t, name)&.lines(chomp: true) }
      next unless shipped && now && now != shipped

      lines = { "added" => now - shipped, "removed" => shipped - now }.flat_map { |how, ls| ls.map { |l| "  #{how}: #{l}" } }
      "v#{name} has shipped, so its notes in CHANGELOG.md stay as tagged:\n#{lines.join("\n")}\nA new entry belongs in #{FRAGMENTS}/."
    end
  end

  def fold(bodies)
    bodies.each_with_object({}) do |body, sections|
      current = "Changed"
      body.each_line(chomp: true) do |line|
        if (title = line[/\A### (.+)/, 1])
          current = title
        elsif !line.strip.empty?
          (sections[current] ||= []) << line
        end
      end
    end
  end
  private_class_method :fold
end
