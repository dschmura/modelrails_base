require "rails_helper"
require "tmpdir"

load Rails.root.join("bin/release")

RSpec.describe Release do
  let(:workdir) { Pathname.new(Dir.mktmpdir) }
  let(:origin) { workdir.join("origin.git") }
  let(:clone) { workdir.join("app") }
  let(:log) { workdir.join("gh.log") }
  let(:today) { Date.new(2026, 10, 27) }
  let(:pr_view) { {} }
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

  def install_fake_gh
    bin = workdir.join("bin").tap(&:mkpath)
    bin.join("pr_view.json").write(JSON.dump(pr_view))
    bin.join("gh").write(<<~SH)
      #!/bin/sh
      echo "CALL $*" >> "#{log}"
      case "$*" in *"--body-file -"*) echo "BODY<<" >> "#{log}"; cat >> "#{log}"; echo ">>BODY" >> "#{log}" ;; esac
      case "$1 $2" in
        "pr create") echo "https://github.com/me/app/pull/42" ;;
        "pr view") cat "#{bin.join('pr_view.json')}" ;;
        *) : ;;
      esac
    SH
    bin.join("gh").chmod(0o755)
    bin
  end

  def run_release(command, *args, **opts)
    bin = install_fake_gh
    original = ENV["PATH"]
    ENV["PATH"] = "#{bin}:#{original}"
    $stdout = StringIO.new
    described_class.new({ today: today }.merge(opts), root: clone.to_s).run(command, *args)
  ensure
    @output = $stdout.string
    $stdout = STDOUT
    ENV["PATH"] = original
  end

  def calls = log.exist? ? log.read : ""
  def remote_heads = git("ls-remote", "--heads", "origin").lines.map { |l| l.split.last.delete_prefix("refs/heads/") }
  def remote_file(ref, path) = git("show", "#{ref}:#{path}")

  describe "naming" do
    before { setup_repo }

    it "names the first release of the day for the date" do
      run_release("prepare", dry_run: true)

      expect(@output).to include("v2026.10.27")
    end

    it "takes the next free suffix when the day already has a tag or a release branch" do
      git("push", "-q", "origin", "main:refs/tags/v2026.10.27")
      git("push", "-q", "origin", "main:refs/heads/release/2026.10.27-2")
      run_release("prepare", dry_run: true)

      expect(@output).to include("v2026.10.27-3")
    end
  end

  describe "prepare" do
    before { setup_repo }

    it "pushes the cut changelog on a branch from next and queues its PR into next" do
      run_release("prepare")

      expect(remote_heads).to include("changelog/2026.10.27")
      expect(remote_file("origin/changelog/2026.10.27", "CHANGELOG.md")).to eq(ReleaseChangelog.cut(changelog, "2026.10.27").chomp)
      expect(git("rev-parse", "origin/changelog/2026.10.27^")).to eq(git("rev-parse", "origin/next"))
      expect(calls).to include("CALL pr create --base next --head changelog/2026.10.27")
      expect(calls).to include("CALL pr merge https://github.com/me/app/pull/42 --auto --merge")
    end

    it "leaves the local checkout untouched" do
      before = git("status", "--porcelain")
      run_release("prepare")

      expect(git("status", "--porcelain")).to eq(before)
    end

    it "changes nothing under --dry-run" do
      run_release("prepare", dry_run: true)

      expect(remote_heads).to contain_exactly("main", "next")
      expect(calls).to be_empty
    end
  end

  describe "cut" do
    let(:prepared) { ReleaseChangelog.cut(changelog, "2026.10.27").sub("## [Unreleased]\n", "## [Unreleased]\n\n### Added\n\n- Landed after prepare.\n") }

    it "pushes release/<name> at next and opens the release PR with what ships" do
      setup_repo(next_changelog: prepared)
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
      setup_repo(next_changelog: prepared)
      git("push", "-q", "origin", "main:refs/tags/v2026.10.27")

      expect { run_release("cut") }.to raise_error(Release::Error, /already shipped/)
    end
  end

  describe "ship" do
    let(:pr_view) { { "headRefName" => "release/2026.10.27", "baseRefName" => "main", "mergeCommit" => { "oid" => @main_sha } } }

    before do
      setup_repo
      @main_sha = git("rev-parse", "origin/main")
    end

    it "merges only the reviewed commit, tags the merge and queues the merge-back into next" do
      run_release("ship", "42", "abc1234")

      expect(calls).to include("CALL pr merge 42 --merge --match-head-commit abc1234")
      expect(git("rev-parse", "v2026.10.27^{commit}")).to eq(@main_sha)
      expect(git("ls-remote", "--tags", "origin")).to include("refs/tags/v2026.10.27")
      expect(git("rev-parse", "origin/sync/2026.10.27")).to eq(@main_sha)
      expect(calls).to include("CALL pr create --base next --head sync/2026.10.27")
      expect(calls).to include("--auto --merge")
    end

    context "when the PR is not a release into main" do
      let(:pr_view) { { "headRefName" => "feature/x", "baseRefName" => "next", "mergeCommit" => nil } }

      it "refuses before merging anything" do
        expect { run_release("ship", "42", "abc1234") }.to raise_error(Release::Error, /release\/\* branch into main/)
        expect(calls).not_to include("pr merge")
      end
    end
  end

  describe "sync, after a hotfix" do
    it "queues main's merge-back into next from a branch named for main's commit" do
      setup_repo
      short = git("rev-parse", "--short=7", "origin/main")
      run_release("sync")

      expect(remote_heads).to include("sync/main-#{short}")
      expect(calls).to include("CALL pr create --base next --head sync/main-#{short}")
    end
  end
end
