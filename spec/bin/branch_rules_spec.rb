require "rails_helper"
require "tmpdir"

load Rails.root.join("bin/branch-rules")

RSpec.describe BranchRules do
  let(:workdir) { Pathname.new(Dir.mktmpdir) }
  let(:log) { workdir.join("gh.log") }
  let(:existing_rulesets) { [] }
  let(:next_exists) { false }
  let(:refuse) { nil }

  after { FileUtils.rm_rf(workdir) }

  def install_fake_gh
    bin = workdir.join("bin").tap(&:mkpath)
    bin.join("rulesets.json").write(JSON.dump(existing_rulesets))
    bin.join("gh").write(<<~SH)
      #!/bin/sh
      echo "CALL $*" >> "#{log}"
      case "$*" in *"--input -"*) echo "BODY $(cat)" >> "#{log}" ;; esac
      case "$*" in
        *"refs/heads/next"*"sha="*) echo '{}' ;;
        *"git/ref/heads/next"*) #{next_exists ? "echo '{}'" : 'echo "Not Found (HTTP 404)" >&2; exit 1'} ;;
        *"git/ref/heads/main"*) echo "abc123" ;;
        *"-X POST repos/me/app/rulesets --input -"*) #{refuse ? "echo '#{refuse}' >&2; exit 1" : "echo '{}'"} ;;
        *"api repos/me/app/rulesets") cat "#{bin.join('rulesets.json')}" ;;
        *) echo '{}' ;;
      esac
    SH
    bin.join("gh").chmod(0o755)
    bin
  end

  def run_rules(**opts)
    bin = install_fake_gh
    original = ENV["PATH"]
    ENV["PATH"] = "#{bin}:#{original}"
    $stdout = StringIO.new
    described_class.new({ repo: "me/app" }.merge(opts), root: Rails.root).run
  ensure
    @output = $stdout.string
    $stdout = STDOUT
    ENV["PATH"] = original
  end

  def calls = log.exist? ? log.readlines(chomp: true) : []
  def writes = calls.grep(/\ACALL api -X/)

  def posted_rulesets
    calls.each_cons(2).filter_map { |call, body| JSON.parse(body.delete_prefix("BODY ")) if call.include?("rulesets") && body.start_with?("BODY") }
  end

  def approvals(ruleset)
    ruleset["rules"].find { |r| r["type"] == "pull_request" }.dig("parameters", "required_approving_review_count")
  end

  it "applies the main, next and release rulesets with one approval required" do
    run_rules

    expect(posted_rulesets.map { |r| r["name"] }).to contain_exactly("main", "next", "release")
    expect(posted_rulesets.map { |r| approvals(r) }).to all(eq(1))
  end

  it "requires no approval under --solo, since GitHub refuses a self-approval" do
    run_rules(solo: true)

    expect(posted_rulesets.map { |r| approvals(r) }).to all(eq(0))
  end

  it "gives no actor a bypass, which would let an admin's merge skip every rule" do
    run_rules

    expect(posted_rulesets.map { |r| r["bypass_actors"] }).to all(eq([]))
  end

  it "creates next from main's head when the repository has none" do
    run_rules

    expect(writes).to include("CALL api -X POST repos/me/app/git/refs -f ref=refs/heads/next -f sha=abc123")
  end

  context "when next already exists" do
    let(:next_exists) { true }

    it "leaves it alone" do
      run_rules

      expect(writes.grep(/git\/refs/)).to be_empty
    end
  end

  it "makes next the default branch and deletes merged branches" do
    run_rules

    expect(writes).to include("CALL api -X PATCH repos/me/app -f default_branch=next -F delete_branch_on_merge=true -F allow_merge_commit=true")
  end

  context "when a ruleset of the same name exists" do
    let(:existing_rulesets) { [ { "id" => 7, "name" => "next" } ] }

    it "updates it in place rather than adding a second" do
      run_rules

      expect(writes.grep(/rulesets/)).to include("CALL api -X PUT repos/me/app/rulesets/7 --input -")
      expect(writes.grep(/-X POST repos\/me\/app\/rulesets/).size).to eq(2)
    end
  end

  context "when the repository has a ruleset this script does not own" do
    let(:existing_rulesets) { [ { "id" => 9, "name" => "main protection" } ] }

    it "names it so its rules can be reconciled by hand" do
      run_rules

      expect(@output).to include("main protection")
    end
  end

  context "when GitHub refuses a ruleset, as on a private repository without a paid plan" do
    let(:refuse) { "Upgrade to GitHub Pro or make this repository public to enable this feature. (HTTP 403)" }

    it "reports the refusal and fails the run" do
      expect(run_rules).to be(false)
      expect(@output).to include("Upgrade to GitHub Pro")
    end
  end

  it "succeeds when every step applies" do
    expect(run_rules).to be(true)
  end

  it "writes nothing under --dry-run" do
    run_rules(dry_run: true)

    expect(writes).to be_empty
  end
end
