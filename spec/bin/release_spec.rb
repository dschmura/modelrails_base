require "rails_helper"
require "tmpdir"

load Rails.root.join("bin/release")

RSpec.describe Release do
  let(:workdir) { Pathname.new(Dir.mktmpdir) }
  let(:origin) { workdir.join("origin.git") }
  let(:clone) { workdir.join("app") }
  let(:bin) { workdir.join("bin") }
  let(:log) { workdir.join("gh.log") }
  let(:today) { Date.new(2026, 10, 27) }
  let(:gh_create) { 'echo "https://github.com/me/app/pull/42"' }
  let(:gh_merge) { "exit 0" }
  let(:gh_api) { "exit 0" }
  let(:changelog) do
    <<~MD
      # Changelog

      ## [Unreleased]

      ### Added

      - First feature.

      ### Fixed

      - A bug.

      ### Added

      - Second feature.

      ## v2.0.0 — Earlier

      - Old.
    MD
  end
  let(:named) { ReleaseChangelog.name_release(changelog, "2026.10.27") }
  let(:identity) do
    { "GIT_AUTHOR_NAME" => "T", "GIT_AUTHOR_EMAIL" => "t@example.com",
      "GIT_COMMITTER_NAME" => "T", "GIT_COMMITTER_EMAIL" => "t@example.com" }
  end

  around do |example|
    saved = identity.keys.to_h { |k| [ k, ENV.fetch(k, nil) ] }
    ENV.update(identity)
    example.run
  ensure
    saved.each { |k, v| v.nil? ? ENV.delete(k) : ENV[k] = v }
    FileUtils.rm_rf(workdir)
  end

  def git(*args, dir: clone)
    out = IO.popen(Release::CLEAN_GIT_ENV, [ "git", "-C", dir.to_s, *args ], err: [ :child, :out ], &:read)
    raise "git #{args.join(' ')} failed: #{out}" unless $?.success?

    out.strip
  end

  def setup_repo(next_changelog: changelog)
    git("init", "-q", "--bare", "-b", "main", origin.to_s, dir: workdir)
    git("clone", "-q", origin.to_s, clone.to_s, dir: workdir)
    clone.join(".github/PULL_REQUEST_TEMPLATE").mkpath
    clone.join(".github/PULL_REQUEST_TEMPLATE/release.md")
         .write(Rails.root.join(".github/PULL_REQUEST_TEMPLATE/release.md").read)
    clone.join("CHANGELOG.md").write(changelog)
    git("add", "-A")
    git("commit", "-q", "-m", "init")
    git("push", "-q", "origin", "HEAD:main")
    clone.join("CHANGELOG.md").write(next_changelog)
    git("commit", "-q", "-am", "next work", "--allow-empty")
    git("push", "-q", "origin", "HEAD:next")
  end

  # A PR reads OPEN until a --match-head-commit merge succeeds; then MERGED at main's head.
  def install_fake_gh(release_pr: nil)
    bin.mkpath
    bin.join("open.json").write(JSON.dump(release_pr&.merge("state" => "OPEN", "mergeCommit" => nil)))
    bin.join("gh").write(<<~SH)
      #!/bin/sh
      echo "CALL $*" >> "#{log}"
      case "$*" in *"-file -"*) echo "BODY<<" >> "#{log}"; cat >> "#{log}"; echo ">>BODY" >> "#{log}" ;; esac
      case "$*" in
        "pr create"*) #{gh_create} ;;
        "pr view"*"--jq .url"*) echo "https://github.com/me/app/pull/41" ;;
        "pr view"*) if [ -f "#{bin}/merged" ]; then cat "#{bin}/merged.json"; else cat "#{bin}/open.json"; fi ;;
        "pr merge"*"--match-head-commit"*) ( #{gh_merge} ); s=$?; [ $s = 0 ] && touch "#{bin}/merged"; exit $s ;;
        "api -X PUT"*) #{gh_api} ;;
        *) : ;;
      esac
    SH
    bin.join("gh").chmod(0o755)
  end

  def mark_merged(release_pr, oid)
    bin.join("merged.json").write(JSON.dump(release_pr.merge("state" => "MERGED", "mergeCommit" => { "oid" => oid })))
  end

  def run_release(command, *args, **opts)
    original_path = ENV["PATH"]
    original_stdout = $stdout
    install_fake_gh unless bin.join("gh").exist?
    ENV["PATH"] = "#{bin}:#{original_path}"
    $stdout = StringIO.new
    described_class.new({ today: today }.merge(opts), root: clone.to_s).run(command, *args)
  ensure
    @output = $stdout.string if $stdout.is_a?(StringIO)
    $stdout = original_stdout
    ENV["PATH"] = original_path
  end

  def calls = log.exist? ? log.read : ""
  def remote_heads = git("ls-remote", "--heads", "origin").lines.map { |l| l.split.last.delete_prefix("refs/heads/") }

  describe "naming" do
    before { setup_repo }

    it "names the first release of the day for the date" do
      run_release("prepare", dry_run: true)

      expect(@output).to include("== Prepare v2026.10.27 ==")
    end

    it "takes the next free suffix when the day already has a tag" do
      git("push", "-q", "origin", "main:refs/tags/v2026.10.27")
      git("push", "-q", "origin", "main:refs/tags/v2026.10.27-2")
      run_release("prepare", dry_run: true)

      expect(@output).to include("== Prepare v2026.10.27-3 ==")
    end
  end

  describe "prepare" do
    it "pushes the named changelog on a branch from next and queues its PR into next" do
      setup_repo
      run_release("prepare")

      expect(git("show", "origin/changelog/2026.10.27:CHANGELOG.md")).to eq(named.chomp)
      expect(git("rev-parse", "origin/changelog/2026.10.27^")).to eq(git("rev-parse", "origin/next"))
      expect(calls).to include("CALL pr create --base next --head changelog/2026.10.27")
      expect(calls).to include("CALL pr merge https://github.com/me/app/pull/42 --auto --merge")
    end

    it "says the PR waits for an approval too, where the rules require one" do
      setup_repo
      run_release("prepare")

      expect(@output).to include("once its checks pass and any required approval is given")
    end

    it "leaves the local checkout untouched" do
      setup_repo
      before = git("status", "--porcelain")
      run_release("prepare")

      expect(git("status", "--porcelain")).to eq(before)
    end

    it "changes nothing under --dry-run" do
      setup_repo
      run_release("prepare", dry_run: true)

      expect(remote_heads).to contain_exactly("main", "next")
      expect(calls).to be_empty
    end

    it "refuses while next names a release that hasn't shipped" do
      setup_repo(next_changelog: named)

      expect { run_release("prepare") }.to raise_error(Release::Error, /v2026\.10\.27 is named but hasn't shipped/)
      expect(remote_heads).to contain_exactly("main", "next")
    end

    it "names the next release once the last one has shipped" do
      setup_repo(next_changelog: named.sub("## [Unreleased]\n", "## [Unreleased]\n\n### Added\n\n- Later.\n"))
      git("push", "-q", "origin", "main:refs/tags/v2026.10.27")
      run_release("prepare", dry_run: true)

      expect(@output).to include("== Prepare v2026.10.27-2 ==")
    end
  end

  describe "cut" do
    let(:with_later_entry) { named.sub("## [Unreleased]\n", "## [Unreleased]\n\n### Added\n\n- Landed after prepare.\n") }

    it "pushes release/<name> at next and opens the release PR with what ships" do
      setup_repo(next_changelog: with_later_entry)
      run_release("cut")

      expect(git("rev-parse", "origin/release/2026.10.27")).to eq(git("rev-parse", "origin/next"))
      expect(calls).to include("CALL pr create --base main --head release/2026.10.27 --title Release 2026.10.27")
      body = calls[/BODY<<\n(.*?)>>BODY/m, 1]
      expect(body).to include("- Branch: `release/2026.10.27`")
      expect(body).to include("- First feature.\n- Second feature.")
      expect(body).not_to include("Landed after prepare")
    end

    it "refuses until prepare's changelog has landed on next" do
      setup_repo
      expect { run_release("cut") }.to raise_error(Release::Error, /bin\/release prepare/)
    end

    it "refuses a release that already shipped" do
      setup_repo(next_changelog: named)
      git("push", "-q", "origin", "main:refs/tags/v2026.10.27")

      expect { run_release("cut") }.to raise_error(Release::Error, /already shipped/)
    end

    it "refuses while another release branch is open, so staging keeps the one under review" do
      setup_repo(next_changelog: named)
      git("push", "-q", "origin", "main:refs/heads/release/2026.10.26")

      expect { run_release("cut") }.to raise_error(Release::Error, %r{release/2026\.10\.26 is still open})
      expect(remote_heads).not_to include("release/2026.10.27")
    end

    it "refuses until the last merge-back has landed on next" do
      setup_repo(next_changelog: named)
      git("commit", "-q", "--allow-empty", "-m", "hotfix")
      git("push", "-q", "origin", "HEAD:main")

      expect { run_release("cut") }.to raise_error(Release::Error, /main isn't in next yet/)
    end
  end

  describe "ship" do
    let(:release_pr) { { "headRefName" => "release/2026.10.27", "baseRefName" => "main" } }
    let(:main_sha) { git("rev-parse", "origin/main") }

    before do
      setup_repo(next_changelog: named)
      install_fake_gh(release_pr: release_pr)
      mark_merged(release_pr, main_sha)
    end

    it "merges only the reviewed commit, publishes the release and queues the merge-back" do
      run_release("ship", "42", "abc1234")

      expect(calls).to include("CALL pr merge 42 --merge --match-head-commit abc1234")
      expect(calls).to include("CALL release create v2026.10.27 --target #{main_sha} --title Release 2026.10.27 --notes-file -")
      expect(git("rev-parse", "origin/merge-back/2026.10.27")).to eq(main_sha)
      expect(calls).to include("CALL pr create --base next --head merge-back/2026.10.27")
    end

    context "when GitHub refuses the merge because the branch moved" do
      let(:gh_merge) { "echo 'Head branch was modified. Review and try the merge again.' >&2; exit 1" }

      it "stops before publishing or merging back" do
        expect { run_release("ship", "42", "abc1234") }.to raise_error(Release::Error, /Head branch was modified/)
        expect(calls).not_to include("release create")
        expect(remote_heads).not_to include("merge-back/2026.10.27")
      end
    end

    it "skips what a stopped run already did when run again" do
      bin.join("merged").write("")
      git("push", "-q", "origin", "main:refs/tags/v2026.10.27")
      run_release("ship", "42", "abc1234")

      expect(calls).not_to include("--match-head-commit")
      expect(calls).not_to include("release create")
      expect(remote_heads).to include("merge-back/2026.10.27")
    end

    context "when the PR is not a release into main" do
      let(:release_pr) { { "headRefName" => "feature/x", "baseRefName" => "next" } }

      it "refuses before merging anything" do
        expect { run_release("ship", "42", "abc1234") }.to raise_error(Release::Error, %r{release/\* branch into main})
        expect(calls).not_to include("pr merge")
      end
    end
  end

  describe "merge-back, after a hotfix" do
    it "names its branch for main as just fetched" do
      setup_repo
      git("commit", "-q", "--allow-empty", "-m", "hotfix")
      git("push", "-q", "origin", "HEAD:main")
      git("update-ref", "refs/remotes/origin/main", "HEAD~1")
      run_release("merge-back")

      fresh = git("rev-parse", "origin/main")
      expect(git("rev-parse", "origin/merge-back/main-#{fresh[0, 7]}")).to eq(fresh)
    end

    context "when its PR is already open" do
      let(:gh_create) { "echo 'a pull request for branch already exists' >&2; exit 1" }

      it "reuses it" do
        setup_repo
        run_release("merge-back")

        expect(calls).to include("--jq .url")
        expect(@output).to include("pull/41")
      end
    end

    context "when GitHub can't bring the PR up to date" do
      let(:gh_api) { "echo 'merge conflict' >&2; exit 1" }

      it "says so instead of staying quiet" do
        setup_repo
        run_release("merge-back")

        expect(@output).to include("couldn't bring")
      end
    end
  end
end
