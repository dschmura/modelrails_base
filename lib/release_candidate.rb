# frozen_string_literal: true

require_relative "release_changelog"

# The release PR bin/release ship finds when it isn't named one, and the commit it would ship.
module ReleaseCandidate
  class Error < StandardError; end

  BRANCH = %r{\Arelease/(#{ReleaseChangelog::NAME})\z}

  module_function

  # prs: gh pr list's number, headRefName, state and headRefOid; shipped: whether a release name was published.
  def waiting(prs, usage:, &shipped)
    waiting = prs.select do |pr|
      name = pr["headRefName"][BRANCH, 1]
      name && (pr["state"] == "OPEN" || (pr["state"] == "MERGED" && !shipped.call(name)))
    end
    raise Error, "No release PR is waiting to ship: bin/release cut opens one" if waiting.empty?
    raise Error, "#{waiting.map { |pr| "##{pr['number']}" }.join(' and ')} are waiting to ship: name one, #{usage}" if waiting.size > 1

    waiting.first
  end

  # runs: gh run list's headSha and conclusion for the release branch's staging deploys, newest first.
  def found(pr, runs)
    head = pr["headRefOid"]
    deployed = runs.find { |run| run["conclusion"] == "success" }&.dig("headSha")
    return "the branch's head; no successful staging deploy found for it" unless deployed
    return "the commit staging's last deploy ran" if deployed == head

    raise Error, "staging last ran #{deployed[0, 7]}, but #{pr['headRefName']} is at #{head[0, 7]}: review its deploy, " \
                 "or name the commit you reviewed, bin/release ship #{pr['number']} <commit>"
  end

  def confirmed?(pr, head)
    raise Error, "No terminal to confirm on: name the PR and commit, bin/release ship #{pr} #{head[0, 7]}" unless $stdin.tty?

    print("Ship #{head[0, 7]}? [y/N] ")
    $stdin.gets.to_s.strip.casecmp?("y")
  end
end
