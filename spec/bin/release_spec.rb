require "rails_helper"
require "tmpdir"

load Rails.root.join("bin/release")

RSpec.describe Release do
  let(:workdir) { Pathname.new(Dir.mktmpdir) }
  let(:origin) { workdir.join("origin.git") }
  let(:clone) { workdir.join("app") }
  let(:bin) { workdir.join("bin") }
  let(:log) { workdir.join("gh.log") }
  let(:repos_log) { workdir.join("gh_repo.log") }
  let(:today) { Date.new(2026, 10, 27) }
  let(:gh_create) { 'echo "https://github.com/me/app/pull/42"' }
  let(:gh_merge) { "exit 0" }
  let(:gh_api) { "exit 0" }
  let(:gh_runs) { %q(echo '[{"status":"completed","conclusion":"success"}]') }
  let(:gh_prs) { "echo '[]'" }
  let(:gh_deploys) { "echo '[]'" }
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
    git("remote", "set-url", "origin", "git@github.com:me/app.git")
    git("config", "url.#{origin}.insteadOf", "git@github.com:me/app.git")
    git("remote", "add", "upstream", "git@github.com:me/template.git")
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
      echo "$GH_REPO" >> "#{repos_log}"
      case "$*" in *"-file -"*) echo "BODY<<" >> "#{log}"; cat >> "#{log}"; echo ">>BODY" >> "#{log}" ;; esac
      case "$*" in
        "pr create"*) #{gh_create} ;;
        "pr view"*"--jq .url"*) echo "https://github.com/me/app/pull/41" ;;
        "pr list"*) #{gh_prs} ;;
        "pr view"*) if [ -f "#{bin}/merged" ]; then cat "#{bin}/merged.json"; else cat "#{bin}/open.json"; fi ;;
        "pr merge"*"--match-head-commit"*) ( #{gh_merge} ); s=$?; [ $s = 0 ] && touch "#{bin}/merged"; exit $s ;;
        "api -X PUT"*) #{gh_api} ;;
        "run list --workflow deploy.yml"*) #{gh_deploys} ;;
        "run list"*) #{gh_runs} ;;
        *) : ;;
      esac
    SH
    bin.join("gh").chmod(0o755)
  end

  def mark_merged(release_pr, oid)
    bin.join("merged.json").write(JSON.dump(release_pr.merge("state" => "MERGED", "mergeCommit" => { "oid" => oid })))
  end

  def run_release(command, *args, stdin: StringIO.new, **opts)
    original_path = ENV["PATH"]
    original_stdout = $stdout
    original_stdin = $stdin
    install_fake_gh unless bin.join("gh").exist?
    ENV["PATH"] = "#{bin}:#{original_path}"
    $stdout = StringIO.new
    $stdin = stdin
    described_class.new({ today: today }.merge(opts), root: clone.to_s).run(command, *args)
  ensure
    @output = $stdout.string if $stdout.is_a?(StringIO)
    $stdout = original_stdout
    $stdin = original_stdin
    ENV["PATH"] = original_path
  end

  def terminal(answer) = StringIO.new(answer).tap { |io| io.define_singleton_method(:tty?) { true } }

  def calls = log.exist? ? log.read : ""
  def remote_heads = git("ls-remote", "--heads", "origin").lines.map { |l| l.split.last.delete_prefix("refs/heads/") }

  def add_fragment(name, text)
    clone.join("changelog.d").mkpath
    clone.join("changelog.d/README.md").write("How to add a changelog entry.\n")
    clone.join("changelog.d/#{name}").write(text)
    git("add", "-A")
    git("commit", "-q", "-m", "fragment #{name}")
    git("push", "-q", "origin", "HEAD:next")
  end

  describe "the repository it acts on" do
    it "is origin's, not upstream's, which gh would pick" do
      setup_repo(next_changelog: named)
      run_release("cut")

      expect(repos_log.readlines(chomp: true)).to all(eq("me/app")).and be_any
    end

    it "is never guessed: with origin outside GitHub it stops before acting" do
      setup_repo(next_changelog: named)
      git("remote", "set-url", "origin", origin.to_s)

      expect { run_release("cut") }.to raise_error(Release::Error, /origin isn't a GitHub repository/)
      expect(calls).to be_empty
      expect(remote_heads).not_to include("release/2026.10.27")
    end
  end

  describe "pushing" do
    let(:hook_log) { workdir.join("hook.log") }

    def install_failing_pre_push_hook
      hook = Pathname.new(git("rev-parse", "--absolute-git-dir")).join("hooks/pre-push")
      hook.write(<<~SH)
        #!/bin/sh
        echo ran >> "#{hook_log}"
        echo "docker_build: no space left on device"
        for i in 1 2 3 4 5 6; do echo "summary line $i"; done
        exit 1
      SH
      hook.chmod(0o755)
    end

    it "says the pre-push hook is running before a new commit goes through it" do
      setup_repo
      install_failing_pre_push_hook

      expect { run_release("prepare") }.to raise_error(Release::Error)
      expect(@output).to include("the pre-push hook")
      expect(hook_log).to exist
    end

    it "shows what the hook said when it refuses the push, and where the whole of it is" do
      setup_repo
      install_failing_pre_push_hook

      expect { run_release("prepare") }.to raise_error(Release::Error, %r{no space left on device.*tmp/release-push\.log}m)
      expect(clone.join("tmp/release-push.log").read).to include("summary line 6")
    end

    it "skips the hook for a commit already on origin, which it has checked before" do
      setup_repo(next_changelog: named)
      install_failing_pre_push_hook
      run_release("cut")

      expect(remote_heads).to include("release/2026.10.27")
      expect(hook_log).not_to exist
    end
  end

  describe "naming" do
    before { setup_repo }

    it "names the first release of the day for the date, in the repository it acts on" do
      run_release("prepare", dry_run: true)

      expect(@output).to include("== Prepare v2026.10.27 in me/app ==")
    end

    it "takes the next free suffix when the day already has a tag" do
      git("push", "-q", "origin", "main:refs/tags/v2026.10.27")
      git("push", "-q", "origin", "main:refs/tags/v2026.10.27-2")
      run_release("prepare", dry_run: true)

      expect(@output).to include("== Prepare v2026.10.27-3 in me/app ==")
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

    it "gathers changelog.d's fragments into the named release and deletes them, keeping the README" do
      setup_repo
      add_fragment("fix-login.md", "### Fixed\n\n- Login works.\n")
      run_release("prepare")

      section = ReleaseChangelog.section(git("show", "origin/changelog/2026.10.27:CHANGELOG.md"), "2026.10.27")
      expect(section).to include("### Fixed\n\n- A bug.\n- Login works.").and include("- First feature.")
      expect(git("ls-tree", "--name-only", "origin/changelog/2026.10.27", "changelog.d/")).to eq("changelog.d/README.md")
    end

    it "starts a release under --if-needed from fragments alone" do
      setup_repo(next_changelog: named)
      git("push", "-q", "origin", "main:refs/tags/v2026.10.27")
      add_fragment("fix-login.md", "- Login works.\n")
      run_release("prepare", if_needed: true)

      expect(remote_heads).to include("changelog/2026.10.27-2")
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

    it "refuses while an earlier changelog PR hasn't merged" do
      setup_repo
      git("push", "-q", "origin", "origin/next:refs/heads/changelog/2026.10.26")

      expect { run_release("prepare") }.to raise_error(Release::Error, %r{changelog/2026\.10\.26 hasn't merged})
      expect(remote_heads).not_to include("changelog/2026.10.27")
    end

    it "starts no release under --if-needed when no changelog entry is waiting, and says so" do
      setup_repo(next_changelog: named)
      git("push", "-q", "origin", "main:refs/tags/v2026.10.27")
      run_release("prepare", if_needed: true)

      expect(@output).to include("No changelog entries are waiting on next")
      expect(remote_heads).to contain_exactly("main", "next")
    end

    it "starts no release under --if-needed while one is under way, and says which" do
      setup_repo(next_changelog: named.sub("## [Unreleased]\n", "## [Unreleased]\n\n### Added\n\n- Later.\n"))
      run_release("prepare", if_needed: true)

      expect(@output).to include("v2026.10.27 is named but hasn't shipped, so the next release waits for it")
      expect(remote_heads).to contain_exactly("main", "next")
    end

    it "starts no release under --if-needed while a changelog PR is waiting to merge" do
      setup_repo
      git("push", "-q", "origin", "origin/next:refs/heads/changelog/2026.10.27")
      run_release("prepare", if_needed: true)

      expect(@output).to include("changelog/2026.10.27 hasn't merged")
      expect(calls).not_to include("pr create")
    end

    it "names the release as usual under --if-needed when [Unreleased] has entries" do
      setup_repo
      run_release("prepare", if_needed: true)

      expect(remote_heads).to include("changelog/2026.10.27")
    end

    it "names the next release once the last one has shipped" do
      setup_repo(next_changelog: named.sub("## [Unreleased]\n", "## [Unreleased]\n\n### Added\n\n- Later.\n"))
      git("push", "-q", "origin", "main:refs/tags/v2026.10.27")
      run_release("prepare", dry_run: true)

      expect(@output).to include("== Prepare v2026.10.27-2 in me/app ==")
    end
  end

  describe "cut" do
    let(:with_later_entry) { named.sub("## [Unreleased]\n", "## [Unreleased]\n\n### Added\n\n- Landed after prepare.\n") }

    def land_on_next(changelog: nil, file: nil)
      clone.join("CHANGELOG.md").write(changelog) if changelog
      clone.join(file).write("#{file}\n") if file
      git("add", "-A")
      git("commit", "-q", "-m", "landed on next")
      git("push", "-q", "origin", "HEAD:next")
    end

    it "pushes release/<name> at next and opens the release PR with what ships" do
      setup_repo(next_changelog: named)
      run_release("cut")

      expect(git("rev-parse", "origin/release/2026.10.27")).to eq(git("rev-parse", "origin/next"))
      expect(calls).to include("CALL pr create --base main --head release/2026.10.27 --title Release 2026.10.27")
      body = calls[/BODY<<\n(.*?)>>BODY/m, 1]
      expect(body).to include("- Branch: `release/2026.10.27`")
      expect(body).to include("- First feature.\n- Second feature.")
    end

    it "cuts before the first PR that landed a changelog line after the release was named" do
      setup_repo(next_changelog: named)
      named_at = git("rev-parse", "origin/next")
      land_on_next(changelog: with_later_entry, file: "later.rb")
      run_release("cut")

      expect(git("rev-parse", "origin/release/2026.10.27")).to eq(named_at)
      expect(calls[/BODY<<\n(.*?)>>BODY/m, 1]).not_to include("Landed after prepare")
      expect(@output).to include("1 later commit on next waits for the next release")
    end

    it "cuts before a fragment that landed after the release was named" do
      setup_repo(next_changelog: named)
      named_at = git("rev-parse", "origin/next")
      add_fragment("later.md", "- Landed after prepare.\n")
      run_release("cut")

      expect(git("rev-parse", "origin/release/2026.10.27")).to eq(named_at)
      expect(@output).to include("1 later commit on next waits for the next release")
    end

    it "takes along what landed after the name without a changelog line" do
      setup_repo(next_changelog: named)
      land_on_next(file: "docs.md")
      run_release("cut")

      expect(git("rev-parse", "origin/release/2026.10.27")).to eq(git("rev-parse", "origin/next"))
    end

    it "refuses when lines landed under [Unreleased] before the release was named, and lists them" do
      setup_repo(next_changelog: with_later_entry)

      expect { run_release("cut") }.to raise_error(Release::Error, /- Landed after prepare\..*## v2026\.10\.27/m)
      expect(remote_heads).not_to include("release/2026.10.27")
    end

    it "asks CI about the commit it cuts" do
      setup_repo(next_changelog: named)
      run_release("cut")

      expect(calls).to include("CALL run list --workflow ci.yml --commit #{git("rev-parse", "origin/next")} --event push")
    end

    context "when CI failed on the commit it would cut" do
      let(:gh_runs) { %q(echo '[{"status":"completed","conclusion":"failure"}]') }

      it "refuses, and says how a fix joins the release" do
        setup_repo(next_changelog: named)

        expect { run_release("cut") }.to raise_error(Release::Error, /CI failed on \h{7}.*## v2026\.10\.27/m)
        expect(remote_heads).not_to include("release/2026.10.27")
      end
    end

    context "when CI's run on the commit was skipped" do
      let(:gh_runs) { %q(echo '[{"status":"completed","conclusion":"skipped"}]') }

      it "refuses, since a skipped run proves nothing" do
        setup_repo(next_changelog: named)

        expect { run_release("cut") }.to raise_error(Release::Error, /CI failed on \h{7}/)
      end
    end

    context "when CI hasn't finished on the commit it would cut" do
      let(:gh_runs) { %q(echo '[{"status":"in_progress","conclusion":""}]') }

      it "refuses until it passes" do
        setup_repo(next_changelog: named)

        expect { run_release("cut") }.to raise_error(Release::Error, /CI hasn't passed on \h{7} yet/)
        expect(remote_heads).not_to include("release/2026.10.27")
      end
    end

    context "when CI hasn't run on the commit it would cut" do
      let(:gh_runs) { "echo '[]'" }

      it "refuses until it passes" do
        setup_repo(next_changelog: named)

        expect { run_release("cut") }.to raise_error(Release::Error, /CI hasn't passed on \h{7} yet/)
      end
    end

    it "cuts nothing under --if-needed when next names no release waiting to be cut, and says so" do
      setup_repo
      run_release("cut", if_needed: true)

      expect(@output).to include("Nothing to cut")
      expect(remote_heads).to contain_exactly("main", "next")
    end

    it "cuts nothing under --if-needed once the named release is cut" do
      setup_repo(next_changelog: named)
      git("push", "-q", "origin", "origin/next:refs/heads/release/2026.10.27")
      run_release("cut", if_needed: true)

      expect(@output).to include("Nothing to cut")
      expect(calls).not_to include("pr create")
    end

    it "cuts as usual under --if-needed when a named release is waiting" do
      setup_repo(next_changelog: named)
      run_release("cut", if_needed: true)

      expect(remote_heads).to include("release/2026.10.27")
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

    it "picks up its own branch when a stopped run already pushed it" do
      setup_repo(next_changelog: named)
      git("push", "-q", "origin", "origin/next:refs/heads/release/2026.10.27")
      run_release("cut")

      expect(calls).to include("CALL pr create --base main --head release/2026.10.27")
    end

    context "when GitHub refuses to open the PR for a reason other than an open one" do
      let(:gh_create) { "echo 'Body is too long (maximum is 65536 characters)' >&2; exit 1" }

      it "reports GitHub's reason" do
        setup_repo(next_changelog: named)

        expect { run_release("cut") }.to raise_error(Release::Error, /Body is too long/)
        expect(calls).not_to include("--jq .url")
      end
    end

    it "trims what ships to fit GitHub's limit and points to the full section" do
      long = named.sub("- First feature.\n", "- First feature.\n" + ("- An entry long enough to add up quickly across a release.\n" * 1500))
      setup_repo(next_changelog: long)
      run_release("cut")

      body = calls[/BODY<<\n(.*?)>>BODY/m, 1]
      expect(body.length).to be <= Release::BODY_LIMIT
      expect(body).to include("CHANGELOG.md on release/2026.10.27")
      expect(body).to include("bin/release ship")
    end

    it "refuses until the last merge-back has landed on next" do
      setup_repo(next_changelog: named)
      git("commit", "-q", "--allow-empty", "-m", "hotfix")
      git("push", "-q", "origin", "HEAD:main")

      expect { run_release("cut") }.to raise_error(Release::Error, /main isn't in next yet/)
    end
  end

  describe "in a fork, whose changelog carries the template's releases" do
    let(:template) { workdir.join("template.git") }
    let(:with_fork_entry) { named.sub("## [Unreleased]\n", "## [Unreleased]\n\n### Added\n\n- A fork feature.\n") }

    # The template tags v2026.10.27 at `tagged`; next gains the .fork.yml that bin/fork commits.
    def fork_from_template(tagged: "origin/next", template_url: "git@github.com:me/template.git")
      git("init", "-q", "--bare", template.to_s, dir: workdir)
      git("config", "url.#{template}.insteadOf", "https://github.com/me/template.git")
      git("push", "-q", template.to_s, "#{git('rev-parse', tagged)}:refs/tags/v2026.10.27")
      clone.join(".fork.yml").write({ "name" => "app", "template_url" => template_url }.to_yaml)
      git("add", ".fork.yml")
      git("commit", "-q", "-m", "fork")
      git("push", "-q", "origin", "HEAD:next")
    end

    def commit_outside_next = git("commit-tree", "HEAD^{tree}", "-m", "the template's own")

    it "starts its own release past one the template shipped" do
      setup_repo(next_changelog: with_fork_entry)
      fork_from_template
      run_release("prepare", if_needed: true, dry_run: true)

      expect(@output).to include("== Prepare v2026.10.27-2 in me/app ==")
    end

    it "has nothing to cut when the release next names is one the template shipped" do
      setup_repo(next_changelog: named)
      fork_from_template
      run_release("cut", if_needed: true)

      expect(@output).to include("Nothing to cut")
      expect(remote_heads).to contain_exactly("main", "next")
    end

    it "still cuts its own release when the template tagged the same name on a commit next doesn't have" do
      setup_repo(next_changelog: named)
      fork_from_template(tagged: commit_outside_next)
      run_release("cut", if_needed: true)

      expect(remote_heads).to include("release/2026.10.27")
    end

    it "never names a release after one the template tagged" do
      setup_repo
      fork_from_template(tagged: commit_outside_next)
      run_release("prepare", dry_run: true)

      expect(@output).to include("== Prepare v2026.10.27-2 in me/app ==")
    end

    it "stops, rather than guess, when it can't read the template's tags" do
      setup_repo(next_changelog: named)
      fork_from_template(template_url: "git@github.com:me/private-template.git")
      git("config", "url.#{workdir.join('unreadable.git')}.insteadOf", "https://github.com/me/private-template.git")

      expect { run_release("cut", if_needed: true) }
        .to raise_error(Release::Error, %r{can't read the tags of me/private-template})
    end
  end

  describe "check" do
    def ship_named_release
      setup_repo(next_changelog: named)
      git("tag", "v2026.10.27")
    end

    it "passes while each tagged release's notes read as they did at the tag" do
      ship_named_release
      clone.join("CHANGELOG.md").write(named.sub("## [Unreleased]\n", "## [Unreleased]\n\n### Added\n\n- Next feature.\n"))
      git("commit", "-q", "-am", "next work")

      run_release("check")

      expect(@output).to include("Shipped release notes are unchanged")
    end

    it "fails when a line lands in a shipped release, and names the line" do
      ship_named_release
      clone.join("CHANGELOG.md").write(named.sub("- A bug.\n", "- A bug.\n- A late fix.\n"))
      git("commit", "-q", "-am", "a line in the wrong place")

      expect { run_release("check") }
        .to raise_error(Release::Error, %r{v2026\.10\.27 has shipped.*- A late fix\..*changelog\.d/}m)
    end

    it "fails when a line is removed from a shipped release" do
      ship_named_release
      clone.join("CHANGELOG.md").write(named.sub("- A bug.\n", ""))
      git("commit", "-q", "-am", "a line lost")

      expect { run_release("check") }.to raise_error(Release::Error, /v2026\.10\.27 has shipped.*- A bug\./m)
    end

    it "leaves untagged releases alone: a named one waiting to ship, or one a fork inherited" do
      setup_repo(next_changelog: named)
      clone.join("CHANGELOG.md").write(named.sub("- A bug.\n", "- A bug.\n- Added before the cut.\n"))
      git("commit", "-q", "-am", "edit before shipping")

      run_release("check")

      expect(@output).to include("Shipped release notes are unchanged")
    end
  end

  describe "ship" do
    let(:head) { "abc1234#{'0' * 33}" }
    let(:release_pr) { { "headRefName" => "release/2026.10.27", "baseRefName" => "main", "headRefOid" => head } }
    let(:main_sha) { git("rev-parse", "origin/main") }

    before do
      setup_repo(next_changelog: named)
      install_fake_gh(release_pr: release_pr)
      mark_merged(release_pr, main_sha)
    end

    it "merges only the reviewed commit, publishes the release and queues the merge-back" do
      run_release("ship", "42", "abc1234")

      expect(calls).to include("CALL pr merge 42 --merge --match-head-commit #{head}")
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

    it "trims the release notes to fit GitHub's limit" do
      long = named.sub("- First feature.\n", "- First feature.\n" + ("- An entry long enough to add up quickly across a release.\n" * 2500))
      clone.join("CHANGELOG.md").write(long)
      git("commit", "-q", "-am", "long")
      git("push", "-q", "origin", "HEAD:main")
      mark_merged(release_pr, git("rev-parse", "HEAD"))
      run_release("ship", "42", "abc1234")

      notes = calls[/CALL release create.*?BODY<<\n(.*?)>>BODY/m, 1]
      expect(notes.length).to be <= Release::BODY_LIMIT
      expect(notes).to include("CHANGELOG.md")
    end

    it "skips what a stopped run already did when run again" do
      bin.join("merged").write("")
      git("push", "-q", "origin", "main:refs/tags/v2026.10.27")
      run_release("ship", "42", "abc1234")

      expect(calls).not_to include("--match-head-commit")
      expect(calls).not_to include("release create")
      expect(remote_heads).to include("merge-back/2026.10.27")
    end

    it "refuses an already-merged PR whose merged head isn't the reviewed commit" do
      bin.join("merged").write("")

      expect { run_release("ship", "42", "def5678") }.to raise_error(Release::Error, /merged at abc1234, not def5678/)
      expect(calls).not_to include("release create")
      expect(remote_heads).not_to include("merge-back/2026.10.27")
    end

    it "refuses an open PR whose branch isn't at the reviewed commit" do
      expect { run_release("ship", "42", "def5678") }.to raise_error(Release::Error, /PR 42 is at abc1234, not def5678/)
      expect(calls).not_to include("pr merge")
    end

    it "refuses a PR given without the commit reviewed on staging" do
      expect { run_release("ship", "42") }.to raise_error(Release::Error, /usage: bin\/release ship/)
      expect(calls).not_to include("pr merge")
    end

    describe "with nothing named, finding the release waiting to ship" do
      let(:gh_prs) { %(echo '[{"number":42,"headRefName":"release/2026.10.27","state":"OPEN","headRefOid":"#{head}"}]') }
      let(:gh_deploys) { %(echo '[{"headSha":"#{head}","conclusion":"success"}]') }

      it "ships the commit staging ran once you say yes" do
        run_release("ship", stdin: terminal("y\n"))

        expect(@output).to include("PR #42, release/2026.10.27 into main, at abc1234: the commit staging's last deploy ran")
        expect(calls).to include("CALL run list --workflow deploy.yml --branch release/2026.10.27 --event push")
        expect(calls).to include("CALL pr merge 42 --merge --match-head-commit #{head}")
        expect(calls).to include("CALL release create v2026.10.27")
      end

      it "ships nothing when you don't say yes" do
        run_release("ship", stdin: terminal("\n"))

        expect(@output).to include("Not shipped.")
        expect(calls).not_to include("pr merge")
      end

      it "asks for the PR and commit by name when there's no terminal to confirm on" do
        expect { run_release("ship") }.to raise_error(ReleaseCandidate::Error, /bin\/release ship 42 abc1234/)
        expect(calls).not_to include("pr merge")
      end

      it "shows what it found without asking on a dry run" do
        run_release("ship", dry_run: true)

        expect(@output).to include("PR #42, release/2026.10.27 into main, at abc1234")
        expect(@output).to include("[dry-run] would merge PR 42 at abc1234")
        expect(calls).not_to include("pr merge")
      end

      context "when the branch has moved past what staging ran" do
        let(:gh_deploys) { %(echo '[{"headSha":"def5678#{'0' * 33}","conclusion":"success"}]') }

        it "refuses, naming both commits" do
          expect { run_release("ship", stdin: terminal("y\n")) }
            .to raise_error(ReleaseCandidate::Error, %r{staging last ran def5678, but release/2026\.10\.27 is at abc1234})
          expect(calls).not_to include("pr merge")
        end
      end

      context "when staging has no successful deploy of the branch" do
        let(:gh_deploys) { %(echo '[{"headSha":"#{head}","conclusion":"skipped"}]') }

        it "offers the branch's head and says no staging deploy was found" do
          run_release("ship", stdin: terminal("y\n"))

          expect(@output).to include("at abc1234: the branch's head; no successful staging deploy found for it")
          expect(calls).to include("CALL pr merge 42 --merge --match-head-commit #{head}")
        end
      end

      context "when the release PR was merged on GitHub and not yet published" do
        let(:gh_prs) { %(echo '[{"number":42,"headRefName":"release/2026.10.27","state":"MERGED","headRefOid":"#{head}"}]') }

        it "finishes shipping it" do
          bin.join("merged").write("")
          run_release("ship", stdin: terminal("y\n"))

          expect(@output).to include("✓ PR 42 already merged")
          expect(calls).to include("CALL release create v2026.10.27")
        end
      end

      context "when every release PR has shipped" do
        let(:gh_prs) { %(echo '[{"number":41,"headRefName":"release/2026.10.27","state":"MERGED","headRefOid":"#{head}"}]') }

        it "says there's nothing to ship" do
          git("push", "-q", "origin", "main:refs/tags/v2026.10.27")

          expect { run_release("ship", stdin: terminal("y\n")) }.to raise_error(ReleaseCandidate::Error, /No release PR is waiting to ship/)
        end
      end

      context "when two release PRs are waiting" do
        let(:gh_prs) do
          %(echo '[{"number":42,"headRefName":"release/2026.10.27","state":"OPEN","headRefOid":"#{head}"},) +
            %({"number":43,"headRefName":"release/2026.10.28","state":"OPEN","headRefOid":"#{head}"}]')
        end

        it "asks which one" do
          expect { run_release("ship", stdin: terminal("y\n")) }.to raise_error(ReleaseCandidate::Error, /#42 and #43 are waiting to ship/)
        end
      end
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

    context "when the PR is already up to date" do
      let(:gh_api) { "echo 'gh: There are no new commits on the base branch. (HTTP 422)' >&2; exit 1" }

      it "doesn't warn" do
        setup_repo
        run_release("merge-back")

        expect(@output).not_to include("couldn't bring")
      end
    end
  end
end
