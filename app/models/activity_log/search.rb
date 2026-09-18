class ActivityLog < ApplicationRecord
  # The ledger's one search box, resolved once per request: an email address, a
  # person's name, a workspace or a project, all four branches evaluated and
  # OR'd. A value, not an orchestrator — it answers which records the query
  # named and never filters the feed itself (`ActivityLog.matching_any` does).
  #
  # Names are non-deterministically encrypted (#902), so they are matched the
  # one way this app sanctions: load, decrypt, plain case-insensitive substring
  # in Ruby — `WorkspaceRoster`'s technique at instance scale, which is why the
  # two caps below exist. See /docs/developer/security (Personal Data at Rest).
  class Search
    # The decrypt pass measured 0.012 ms a row on this machine, so the cap is
    # about 24 ms of CPU per search — a request's worth, not a page's. Above it
    # names are not searched at all and the box falls back to the exact-email
    # lookup, which is SQL.
    NAME_SEARCH_LIMIT = 2_000
    # A one-letter query must not build an OR list of the whole instance.
    RESULT_LIMIT = 50

    attr_reader :query, :users, :workspaces, :projects

    def self.resolve(query, reach:)
      needle = query.to_s.strip.downcase.presence
      return new(query: nil) unless needle

      skipped = User.count > NAME_SEARCH_LIMIT
      new(query: needle, names_skipped: skipped,
          users: matching_users(needle, skipped),
          workspaces: matching_workspaces(needle, reach),
          projects: matching_projects(needle, reach))
    end

    # The email lookup is exact on purpose: `email_address` is deterministically
    # encrypted, so SQL can equal it but never match inside it.
    def self.matching_users(needle, skipped)
      found = Array(User.find_by(email_address: needle))
      return found if skipped

      User.select(:id, :first_name, :last_name).find_each do |user|
        break if found.size >= RESULT_LIMIT

        found << user if user.id != found.first&.id && matches_name?(user, needle)
      end
      found
    end
    private_class_method :matching_users

    def self.matches_name?(user, needle)
      [ user.full_name, user.first_name, user.last_name ]
        .any? { |value| value.to_s.downcase.include?(needle) }
    end
    private_class_method :matches_name?

    # A query is text, never a pattern: "ac_e" matches "Ac_e" and not "Acme"
    # (#454, the same ruling the members page's search rests on). `ESCAPE` is
    # not optional — `sanitize_sql_like` backslash-escapes the wildcards, and
    # without the clause SQLite reads that backslash as a literal character.
    ESCAPED_LIKE = "ESCAPE '\\'".freeze

    # PUBLIC, and a relation rather than an array: the ledger's workspace picker
    # needs the same match with its own limit and a count, and the LIKE/ESCAPE
    # doctrine above must have exactly one home. Workspace names are plaintext
    # (unlike user names), so this is ordinary SQL.
    def self.workspaces_matching(needle, reach:)
      reach.where("LOWER(workspaces.name) LIKE :name #{ESCAPED_LIKE} OR workspaces.slug = :slug",
                  name: "%#{Workspace.sanitize_sql_like(needle.to_s.strip.downcase)}%",
                  slug: needle.to_s.strip.downcase)
    end

    def self.matching_workspaces(needle, reach)
      workspaces_matching(needle, reach: reach).limit(RESULT_LIMIT).to_a
    end
    private_class_method :matching_workspaces

    def self.matching_projects(needle, reach)
      Project.joins(:workspace).merge(reach)
             .where("LOWER(projects.name) LIKE ? #{ESCAPED_LIKE}", "%#{Project.sanitize_sql_like(needle)}%")
             .limit(RESULT_LIMIT).to_a
    end
    private_class_method :matching_projects

    def initialize(query:, users: [], workspaces: [], projects: [], names_skipped: false)
      @query, @users, @workspaces, @projects, @names_skipped =
        query, users, workspaces, projects, names_skipped
    end

    def blank? = query.nil?
    def matched? = users.any? || workspaces.any? || projects.any?
    def names_skipped? = @names_skipped
  end
end
