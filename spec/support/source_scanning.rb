# frozen_string_literal: true

# Shared source-text scanning for the code-smell fences that read app/ as text.
# Both helpers were duplicated byte-for-byte in
# spec/code_smells/notifier_recipients_block_dispatch_spec.rb and
# spec/code_smells/membership_creation_declares_actor_stance_spec.rb; a fix to
# one copy would silently leave the other scanning the old way.
#
# Text scanning is a last resort, used only where the fact being checked has no
# runtime representation — "which call sites pass what argument". A fact the
# app already carries (a class attribute, a declared constant) is read off the
# object instead.
module SourceScanning
  # Blank comment lines rather than deleting them, so reported line numbers
  # still match the real file — and so a comment quoting the scanned shape
  # isn't scanned as an occurrence of it. Also blanks a same-line TRAILING
  # comment (fix round 4, item 3: `foo # ActivityLog.create!(action: "x.y")`
  # used to inject a phantom action), tracking ' and " string state so a `#`
  # inside a string or a `#{}` interpolation is left alone. Conservative, not
  # exact: it does not understand %-literals, heredocs, or regex literals, so
  # a `#` inside one of those could still be misread — none appear in the
  # files these specs scan.
  def without_comments(source)
    source.lines.map { |line| strip_trailing_comment(line) }.join
  end

  def strip_trailing_comment(line)
    return "\n" if line.lstrip.start_with?("#")

    quote = nil
    line.each_char.with_index do |char, index|
      if quote
        quote = nil if char == quote && line[index - 1] != "\\"
      elsif char == '"' || char == "'"
        quote = char
      elsif char == "#"
        return "#{line[0...index]}\n"
      end
    end
    line
  end

  # Index just past the ")" closing the "(" at open_index, or nil when the
  # parentheses never balance. Lets a scanner read a full argument list that
  # contains nested calls and spans lines.
  def balanced_end(source, open_index)
    depth = 0
    index = open_index
    while index < source.length
      case source[index]
      when "(" then depth += 1
      when ")"
        depth -= 1
        return index + 1 if depth.zero?
      end
      index += 1
    end
    nil
  end
end

RSpec.configure do |config|
  config.include SourceScanning
end
