require "rails_helper"

# A form rendered INSIDE a <turbo-frame> submits into that frame by default.
# If its controller answers with a redirect, Turbo fetches the target page and
# keeps only the matching frame — the flash, and anything else the layout
# renders outside the frame, is fetched and thrown away. The user acts and
# nothing visibly happens.
#
# The members page has now produced this bug twice: the magic-link generate
# form (fixed when it was written, with a comment saying why) and the
# invitation row's Resend/Revoke buttons (#1038, which shipped broken and was
# only caught by a reviewer's throwaway spec). Second instance of a bug class
# means a guard rather than a third fix (#659).
#
# Static ERB analysis, not a rendered page: a rendered-page walk can only see
# the frames some spec happened to visit, and the states it happened to reach
# (a row's Reactivate button only exists for a discarded member). The template
# text is the whole population and it is deterministic. The cost is the
# analyser below — a small ERB block-depth tracker — and one real blind spot,
# named in `unwalked` at the bottom: ViewComponent templates are not app views
# and are not walked.
RSpec.describe "Code smell: forms inside Turbo frames" do
  # Locals, not constants (see activity_log_immutability_spec for the CI-shard
  # collision that rule exists to prevent).

  # path => reason. A form here submits into its frame ON PURPOSE, because the
  # action answers with something the frame can absorb: a Turbo Stream, or a
  # render of the frame's own content. An entry is a reviewed decision.
  frame_targeting_is_deliberate = {
    "app/views/sessions/new.html.erb" =>
      "the email lookup posts to sessions/lookups#create, which answers by " \
      "rendering check_email / closed / email_error — each of which carries " \
      "the matching turbo_frame_tag \"sign_in_form\" so Turbo can swap it in " \
      "place. There is no redirect and no flash to lose.",
    "app/views/sessions/lookups/email_error.html.erb" =>
      "the re-render of that same lookup form, inside the same frame, for the " \
      "invalid-address path. Same destination, same in-frame answer.",
    "app/views/workspaces/members/edit.html.erb" =>
      "the role form posts to members#update, which branches on the " \
      "Turbo-Frame header: a frame request gets the role_cell partial back " \
      "(the frame's own content), and the last-owner error gets a toast " \
      "Turbo Stream precisely so the message is not left in a dropped flash."
  }.freeze

  # path => reason, one entry per offending form. These are BROKEN, not
  # allowed: the same #1038 defect, found by this guard's own census and
  # confirmed by hand (each action succeeds; its notice never appears). They
  # are ledgered rather than fixed because fixing them is a behaviour change
  # to three more actions than the issue in hand covers.
  #
  # NOTE FOR THE NEXT TOUCH: this ledger is asserted exactly, so fixing one of
  # these fails this spec until its line is deleted. That is the point — the
  # ledger can only shrink.
  unfixed_offenders = {
    "app/views/workspaces/members/_member_row.html.erb button_to workspace_member_path" =>
      "Deactivate: members#destroy redirects with a `.deactivated` notice " \
      "(and, when you deactivate yourself, to a DIFFERENT page). Both are " \
      "swallowed by members_results.",
    "app/views/workspaces/members/_member_row.html.erb button_to workspace_member_reactivation_path" =>
      "Reactivate: reactivations#create redirects with a `.reactivated` " \
      "notice. Swallowed.",
    "app/views/workspaces/members/_member_row.html.erb button_to workspace_member_ownership_transfer_path" =>
      "Transfer ownership: ownership_transfers#create redirects with a " \
      "`.transferred` notice. Swallowed — and this one hands the workspace " \
      "to someone else with no confirmation that it happened."
  }.freeze

  view_root = Rails.root.join("app/views")

  # --- the analyser -------------------------------------------------------
  # An ERB tag's code, minus the delimiters. `<%#` comments are dropped
  # wholesale: prose is allowed to contain the words "do" and "end".
  erb_tags = lambda do |source|
    source.to_enum(:scan, /<%(?!#)(=|-|)?(.*?)-?%>/m).map do
      match = Regexp.last_match
      { code: match[2].strip, offset: match.begin(0) }
    end
  end

  opens_block = lambda do |code|
    code.match?(/\bdo\s*(\|[^|]*\|)?\z/) ||
      code.match?(/\A(if|unless|case|begin|while|until)\b/)
  end

  closes_block = ->(code) { code.match?(/\Aend\b/) }

  # The tags that sit inside a turbo_frame_tag block in this template. A
  # partial reached FROM inside a frame is entirely inside one, which is what
  # `all_inside` expresses.
  tags_inside_frames = lambda do |source, all_inside|
    tags = erb_tags.call(source)
    return tags if all_inside

    inside = []
    frame_depths = []
    depth = 0
    tags.each do |tag|
      opening = opens_block.call(tag[:code])
      inside << tag if frame_depths.any?

      if closes_block.call(tag[:code])
        depth -= 1
        frame_depths.pop if frame_depths.last == depth
      elsif opening
        frame_depths << depth if tag[:code].match?(/\bturbo_frame_tag\b/)
        depth += 1
      end
    end
    inside
  end

  # "helper path_helper" — stable across reformatting, unlike a line number.
  signature = lambda do |code|
    helper = code[/\b(button_to|form_with|form_for|form_tag)\b/, 1]
    target = code[/\b(\w+_path)\b/, 1] || code[/\b(\w+_url)\b/, 1] || "?"
    "#{helper} #{target}"
  end

  # A partial name as written in `render`, resolved to a file.
  resolve_partial = lambda do |name, from_relative|
    parts = name.split("/")
    base = parts.pop
    dir = parts.any? ? parts.join("/") : File.dirname(from_relative).sub("app/views/", "")
    Rails.root.join("app/views", dir, "_#{base}.html.erb")
  end

  census = lambda do
    found = { top: [], named: [], bare: [] }
    seen = []

    walk = lambda do |path, all_inside|
      relative = path.relative_path_from(Rails.root).to_s
      next if seen.include?([ relative, all_inside ]) || !path.exist?
      seen << [ relative, all_inside ]

      source = path.read
      tags_inside_frames.call(source, all_inside).each do |tag|
        code = tag[:code]

        if code.match?(/\b(button_to|form_with|form_for|form_tag)\b/)
          entry = { site: "#{relative} #{signature.call(code)}", code: code }
          if code.match?(/turbo_frame:\s*(:_top|["']_top["'])/) ||
             code.match?(/data-turbo-frame=["']_top["']/)
            found[:top] << entry
          elsif (name = code[/turbo_frame:\s*["']([^"']+)["']/, 1])
            found[:named] << entry.merge(frame: name)
          else
            found[:bare] << entry
          end
        end

        code.scan(/render\s+(?:layout:\s*|partial:\s*)?["']([\w\/]+)["']/) do |(name)|
          walk.call(resolve_partial.call(name, relative), true)
        end
      end
    end

    Pathname.glob(view_root.join("**/*.erb")).sort.each do |path|
      next unless path.read.include?("turbo_frame_tag")
      walk.call(path, false)
    end

    found
  end

  let(:found) { census.call }

  it "every form inside a Turbo frame either escapes to _top, names its frame, or is a reviewed exception" do
    offenders = found[:bare].reject do |entry|
      relative = entry[:site].split(" ").first
      frame_targeting_is_deliberate.key?(relative)
    end

    expect(offenders.map { |e| e[:site] }).to match_array(unfixed_offenders.keys),
      "A form inside a <turbo-frame> submits into that frame, so a redirect's " \
      "flash never reaches the page (#1038). Give it " \
      "`form: { data: { turbo_frame: \"_top\" } }` (button_to) or " \
      "`data: { turbo_frame: \"_top\" }` (form_with) — or, if the action " \
      "answers with a stream or re-renders the frame, add the view to " \
      "frame_targeting_is_deliberate in this spec with its reason.\n" \
      "Unexpected:\n  #{(offenders.map { |e| e[:site] } - unfixed_offenders.keys).join("\n  ")}\n" \
      "Ledgered but no longer found (delete its line):\n  " \
      "#{(unfixed_offenders.keys - offenders.map { |e| e[:site] }).join("\n  ")}"
  end

  # Positive controls. Without these the guard passes just as happily when the
  # walker silently sees nothing — the failure mode that makes a green code
  # smell spec worthless.
  it "sees the two invitation-row buttons that #1038 fixed" do
    expect(found[:top].map { |e| e[:site] }).to include(
      "app/views/workspaces/members/_invitation_row.html.erb button_to workspace_invitation_resend_path",
      "app/views/workspaces/members/_invitation_row.html.erb button_to workspace_invitation_path"
    )
  end

  it "sees the members search form deliberately targeting its own frame" do
    search = found[:named].find { |e| e[:site].start_with?("app/views/workspaces/members/index.html.erb") }

    expect(search).to be_present,
      "The members filter form targets members_results on purpose — a census " \
      "that cannot see it is not reading index.html.erb's frame at all."
    expect(search[:frame]).to eq("members_results")
  end

  it "reaches forms in partials rendered inside a frame, not just the frame's own template" do
    reached = (found[:top] + found[:named] + found[:bare]).map { |e| e[:site] }

    expect(reached).to include(a_string_starting_with("app/views/workspaces/members/_invitation_row.html.erb"))
    expect(reached).to include(a_string_starting_with("app/views/workspaces/members/_member_row.html.erb"))
  end

  it "keeps every exception entry pointed at a real form inside a real frame" do
    all_sites = (found[:top] + found[:named] + found[:bare]).map { |e| e[:site] }

    (frame_targeting_is_deliberate.keys + unfixed_offenders.keys.map { |k| k.split(" ").first }).uniq.each do |path|
      expect(all_sites).to include(a_string_starting_with(path)),
        "#{path} is listed in this spec but the census finds no form inside a " \
        "frame there. Either the view changed and the entry is dead, or the " \
        "walker stopped reaching it."
    end
  end
end
