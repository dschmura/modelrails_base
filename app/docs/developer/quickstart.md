---
title: Quickstart
description: Every step from cloning the template to a deployed product you can sign in to, each with its check
keywords: quickstart start new app fork clone serve deploy first deploy production mail checklist order steps
---

# Quickstart

This page puts the whole path in order, from cloning the template to a deployed
app you can sign in to. Each step names what to run and how to tell it worked,
and links the guide with the details. Follow it top to bottom the first time.
To do something differently from a default, see
[Changing the defaults](changing-the-defaults).

> **Opened by bin/fork?** Step 1 is done, and step 2's setup ran; start with step 2's check.

You need [mise](https://mise.jdx.dev/), the [GitHub CLI](https://cli.github.com/)
signed in (`gh auth login`), Chrome or Chromium for the tests, and, from step 5,
a server and Docker on the machine you deploy from. Activate mise first, so
`bin/fork` runs mise's Ruby and not your system's: add `eval "$(mise activate zsh)"` to `~/.zshrc` (or
`bash` and `~/.bashrc`), then open a new terminal.

## 1. Make the product

```bash
gh repo clone dschmura/modelrails_base my_app
cd my_app
mise install   # Ruby 4.0.9 and the deploy tools
bin/fork
```

`bin/fork` asks these questions, in this order. Enter accepts the answer in
brackets.

1. **Project name?** It defaults to the folder's name.
2. **Display name?** The name people see, in the header, in mail and on the
   shared workspace. It defaults to the project name, capitalized: type
   "Chmura Family" when the default reads "Chmurafamily".
3. **The preset**, by number: how workspaces work at sign-up
   ([Presets](presets)). Leave it blank to decide later.
4. **Support address?** Where users write for help. Leave it blank to set it
   later.
5. **Create the GitHub repo and push next to it?** [Y], asked when the GitHub
   CLI is signed in. Yes brings two more: **GitHub owner** (you, or one of your
   organizations) and **Public or private?** [public]. On GitHub's free plan,
   private also asks **Make it public instead?**, because a free private repo
   can't have branch rules. A checkout that already has an `origin` of your
   own, such as a clone of a GitHub fork, gets **Push next to origin and
   protect it?** [Y] instead.
6. **Does a second person approve PRs?** [N]. Yes makes every PR wait for one
   approval.
7. **Run bin/setup now?** [Y]. That's step 2.
8. **Start the app and open the quickstart?** [Y], asked once `bin/setup`
   succeeds. Yes starts `bin/dev` and opens this page in your browser.

It moves `next` to the template's latest release, renames the app in one
commit, creates your GitHub repo, pushes `next` and protects the branches.
Before its last question it prints its next steps: this page's address, the
things only you can do, such as your product's description and brand mark, and
the command for step 4.

A clone starts on `next`, and `bin/fork` commits the rename there and leaves
you on it. Your own changes go on a branch of their own (step 3).

**Check:** your repo on GitHub doesn't say "forked from", and has `main` and
`next` branches. Details: [Forking](forking).

## 2. Run it on your machine

Say yes when `bin/fork` offers `bin/setup`, or run it yourself. It installs
the dependencies and prepares the database. Then `bin/dev` starts the server.

**Check:** the public [home page](/) loads, and
`bin/parallel-rspec` ends with 0 failures. `bin/dev` keeps its terminal, so run
the tests in a second one. If you left the support address
blank, one spec fails until you set it in `config/locales/en/pages.en.yml`.
On the shared preset, the seed made an owner, `owner@<your_app>.test`: its
sign-in link is waiting at [/letter_opener](/letter_opener).
Details: [Getting Started](getting-started).

## 3. Work by pull request

`next` and `main` are protected, so GitHub refuses a push straight to either.
Every change reaches `next` by a pull request, from a branch of its own:

```bash
git switch -c <branch>        # a new branch, starting from next
# make your change, and write changelog.d/<branch>.md (below)
git add <the files you changed> changelog.d/<branch>.md
git commit -m "Say what changed"
git push -u origin <branch>
gh pr create --base next --title "Say what changed"
```

Each PR adds a changelog file in `changelog.d/`, holding one line that says
what changed for someone using the app:

```markdown
- The help page gives the support address.
```

Give the PR its title with `--title`. `gh pr create --fill` takes the title
from your commit when there's only one, but from the branch name when there
are several. If you committed on `next` by mistake, `git switch -c <branch>`
takes the commit to a new branch, and `git branch -f next origin/next` then
puts `next` back.

A PR merges once `static` and `test` pass on a branch that's up to date with
`next`. Image Scan runs on PRs that change what goes into the production
image; it's advisory and doesn't block a merge.

**Check:** your first PR, such as the support address or the product
description from step 1's list, merges with both checks green. Details:
[Releasing: Before it merges](releasing#before-it-merges) and
[Forking: Protect the branches](forking#protect-the-branches).

## 4. Production secrets and mail

Production refuses to boot without a mail login, because sign-in is an email,
and without encryption keys for personal data. One command sets up both, and
keeps `RAILS_MASTER_KEY`, the key that decrypts the production credentials, in
fnox:

```bash
bin/production-setup
```

It runs three scripts in order and stops at the first that fails. Fix what it
says and run it again: it skips what's already done.

- **Mail:** `bin/mail-setup` asks for your mail provider and its login,
  creates the production credentials if they don't exist yet, and updates
  `config/deploy.yml`. It's skipped once production has a mail login.
- **Encryption keys:** `bin/encryption-setup` adds them to the production
  credentials without printing them.
- **fnox:** `bin/fnox-setup` makes your fnox identity if you don't have one,
  writes `fnox.toml`, and stores `RAILS_MASTER_KEY` there, and staging's key
  when it exists. Deploys read the key from fnox. It needs `age` and `fnox`, which
  `mise install` puts in place.
  [Keep deploy secrets in fnox](deployment#keep-deploy-secrets-in-fnox) says
  why.

Then verify your sending domain with the provider, as its DNS instructions say.

Commit `config/credentials/production.yml.enc` and `fnox.toml`. Save
`config/credentials/production.key` and `~/.config/fnox/age.txt` in a password
manager now. Neither goes in git. Without `production.key` nobody can decrypt
the credentials, and without `age.txt` nobody can read what fnox stores.

**Check:** before that commit, `git status -u` lists
`config/credentials/production.yml.enc` and `fnox.toml`, and neither key. This
prints `fnox has the key`, without printing the key:

```bash
test "$(fnox get RAILS_MASTER_KEY)" = "$(cat config/credentials/production.key)" && echo "fnox has the key"
```

`bin/rails deploy:check` no longer lists the credentials, the mail login or the
encryption keys. What it still lists is step 6's work. To do any of this by
hand, see [Deployment: Set secrets](deployment#3-set-secrets).
[What production needs](required-production-config) lists every input and
where to get it.

## 5. A server

Rent one Linux server. Lock it down before the first deploy: SSH keys only,
a firewall open on ports 22, 80 and 443, automatic security updates, Docker
from Docker's own repository, a host key checked once, and a folder for
backups owned by uid 1000. Running a machine of your own instead? Also do
[Hardware you run yourself](deployment#hardware-you-run-yourself).

**Check:** `ssh root@<server-ip> docker version` prints Docker's version, and
`ssh -o PubkeyAuthentication=no root@<server-ip>` is refused with
`Permission denied (publickey)`. Details:
[Deployment: Prepare the server](deployment#1-prepare-the-server).

## 6. Configure the deploy and go live

In `config/deploy.yml`, set the server's address (exactly one), uncomment
`proxy:` with your domain, match `builder.arch` to the server, set
`RAILS_HOST` and `BACKUP_PATH`, and uncomment the `/srv/backups:/backups` line
under `volumes:` so the backup folder reaches the app. On the shared preset,
also uncomment `TENANCY_OWNER_EMAIL` (you) and
`TENANCY_WORKSPACE_CREATION: disabled`. `bin/rails deploy:check` then says
"Nothing here stops a deploy." Kamal runs the same check before every build,
and stops a deploy that would fail. Point your domain at the server, wait
until `dig +short <your-domain>` prints its IP, then:

```bash
bin/kamal setup     # the first time
bin/kamal deploy    # every time after
```

**Check:** `https://<your-domain>/up` answers `200`, and
`bin/kamal app exec "bin/rails backup:now"` prints the backup it stored.
Details: [Deployment: First deploy](deployment#first-deploy).

## 7. The first account and the first magic link

Sign-up is invite-only by default, so nobody can register yet. Create the
first account the way Day one (linked below) says for your preset. Then sign
in with that address and read the magic link email.

An address with no account gets the normal page and no email. That's
invite-only working, not a mail failure; test other addresses by inviting
them. If your own link never arrives, `bin/kamal app logs` shows the failed
job with the provider's answer.

**Check:** you're signed in to production. Details:
[Instance operations: Day one](operations#day-one-on-an-invite-only-instance).

## 8. Ship changes

PRs collect in `next`, which deploys nowhere. A release takes them to
production:

```bash
bin/release prepare   # names the release in a changelog PR that merges itself
bin/release cut       # once that PR merges: opens the release PR into main
bin/release ship      # merges it, tags the version, opens main's merge back into next
```

Until you switch on deploys from CI, deploy `main` from your machine with
`bin/kamal deploy` after each ship. Staging, automatic releases and CI deploys
are optional, and each one is a switch you turn on when you want it:
[Changing the defaults](changing-the-defaults#how-changes-ship) says where.

**Check:** the release appears under your repo's Releases. Details:
[Releasing](releasing) and [Deployment: Deploy from CI](deployment#6-deploy-from-ci).

## 9. Take template updates

When the template releases a fix or a feature you want, `bin/sync` merges it
on a branch and opens a PR into `next`. Your own pages, brand and routes stay
yours.

**Check:** the sync's PR passes `static` and `test` and merges itself. Details:
[Forking: Pull upstream updates](forking#pull-upstream-updates).
