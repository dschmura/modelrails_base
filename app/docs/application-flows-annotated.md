---
title: Application Flows (annotated)
description: A builder's walkthrough of every user journey for developers and designers extending the template — each screen annotated with the why behind it (the framework decision, seam, or guarantee), on top of a domain-model primer.
keywords: wireframes flows annotated builders developers designers why rationale model workspace membership role project tools clientside onboarding seam
audience: [guide, technical]
---

# Application Flows (annotated)

A builder-facing walkthrough for **developers and designers extending this template**. Each screen is annotated with not just *what* happens but **why** — the framework decision, the seam you'd extend, or the guarantee it gives you. The flows themselves are intentionally tight, so an end user shouldn't need this page; it exists to help you reason about and build on the framework. Compare with the [low-fi map](/docs/application-flows) and the [detailed copy reference](/docs/application-flows-detailed).

## The model behind every flow

Five concepts the flows plug into. Knowing these is usually enough to avoid fighting the template.

<svg viewBox="0 0 820 250" width="100%" role="img" aria-label="The domain model. User: one identity and login, reused across workspaces — one person, many memberships. Workspace: the tenant and top-level boundary; Current.workspace scopes data via the Tenanted concern. Membership plus Role (owner, admin, member, viewer): role is per-workspace, not global, with JSON permissions, authorized by Pundit. Project plus tools: belongs to a workspace; enabled tools are a registry stored as enabled_tools JSON and extended in an initializer. ClientAccess: an external client linked to a project — a separate access axis, not a membership, consuming no seat and never entering workspace policies. A user is a member of a workspace via Membership; a workspace has projects; a project can grant ClientAccess to external clients." fill="none" stroke="currentColor" font-family="ui-sans-serif, system-ui, sans-serif">
  <defs><marker id="flowarrow-a0" markerWidth="9" markerHeight="9" refX="6.5" refY="3" orient="auto"><path d="M0,0 L8,3 L0,6 z" fill="currentColor" stroke="none"/></marker></defs>
  <rect x="20" y="30" width="150" height="44" rx="8" stroke-width="1.5"/>
  <text x="32" y="50" font-size="11" font-weight="700" fill="currentColor" stroke="none">User</text>
  <text x="32" y="64" font-size="8" fill="currentColor" stroke="none" opacity="0.6">one identity / login</text>
  <text x="20" y="92" font-size="8.5" font-weight="700" fill="currentColor" stroke="none" opacity="0.7">Why</text>
  <text x="20" y="104" font-size="8" fill="currentColor" stroke="none" opacity="0.6">Reused across workspaces —</text>
  <text x="20" y="115" font-size="8" fill="currentColor" stroke="none" opacity="0.6">one person, many memberships.</text>
  <rect x="190" y="30" width="170" height="44" rx="8" stroke-width="1.5"/>
  <text x="202" y="50" font-size="11" font-weight="700" fill="currentColor" stroke="none">Workspace</text>
  <text x="202" y="64" font-size="8" fill="currentColor" stroke="none" opacity="0.6">the tenant</text>
  <text x="190" y="92" font-size="8.5" font-weight="700" fill="currentColor" stroke="none" opacity="0.7">Why</text>
  <text x="190" y="104" font-size="8" fill="currentColor" stroke="none" opacity="0.6">Top-level boundary.</text>
  <text x="190" y="115" font-size="8" fill="currentColor" stroke="none" opacity="0.6">Current.workspace scopes data (Tenanted).</text>
  <rect x="380" y="30" width="180" height="44" rx="8" stroke-width="1.5"/>
  <text x="392" y="48" font-size="10.5" font-weight="700" fill="currentColor" stroke="none">Membership + Role</text>
  <text x="392" y="63" font-size="8" fill="currentColor" stroke="none" opacity="0.6">owner · admin · member · viewer</text>
  <text x="380" y="92" font-size="8.5" font-weight="700" fill="currentColor" stroke="none" opacity="0.7">Why</text>
  <text x="380" y="104" font-size="8" fill="currentColor" stroke="none" opacity="0.6">Role is per-workspace, not global.</text>
  <text x="380" y="115" font-size="8" fill="currentColor" stroke="none" opacity="0.6">JSON permissions; Pundit authorizes.</text>
  <rect x="580" y="30" width="100" height="44" rx="8" stroke-width="1.5"/>
  <text x="592" y="48" font-size="10.5" font-weight="700" fill="currentColor" stroke="none">Project</text>
  <text x="592" y="63" font-size="8" fill="currentColor" stroke="none" opacity="0.6">+ tools</text>
  <text x="580" y="92" font-size="8.5" font-weight="700" fill="currentColor" stroke="none" opacity="0.7">Why</text>
  <text x="580" y="104" font-size="8" fill="currentColor" stroke="none" opacity="0.6">Tools are a registry</text>
  <text x="580" y="115" font-size="8" fill="currentColor" stroke="none" opacity="0.6">(enabled_tools JSON).</text>
  <rect class="text-accent" x="700" y="30" width="100" height="44" rx="8" stroke-width="2"/>
  <text x="712" y="48" font-size="10" font-weight="700" fill="currentColor" stroke="none" class="text-accent">ClientAccess</text>
  <text x="712" y="63" font-size="8" fill="currentColor" stroke="none" opacity="0.6">client ↔ project</text>
  <text x="700" y="92" font-size="8.5" font-weight="700" fill="currentColor" stroke="none" opacity="0.7">Why</text>
  <text x="700" y="104" font-size="8" fill="currentColor" stroke="none" opacity="0.6">Separate axis — not a</text>
  <text x="700" y="115" font-size="8" fill="currentColor" stroke="none" opacity="0.6">membership. No seat.</text>
  <path d="M170 52 H188" stroke-width="1.5" marker-end="url(#flowarrow-a0)"/>
  <path d="M360 52 H378" stroke-width="1.5" marker-end="url(#flowarrow-a0)"/>
  <path d="M560 52 H578" stroke-width="1.5" marker-end="url(#flowarrow-a0)"/>
  <path d="M680 52 H698" stroke-width="1.5" marker-end="url(#flowarrow-a0)"/>
  <text x="179" y="46" text-anchor="middle" font-size="7" fill="currentColor" stroke="none" opacity="0.5">in</text>
  <text x="369" y="46" text-anchor="middle" font-size="7" fill="currentColor" stroke="none" opacity="0.5">via</text>
  <text x="569" y="46" text-anchor="middle" font-size="7" fill="currentColor" stroke="none" opacity="0.5">has</text>
  <rect x="20" y="140" width="780" height="44" rx="5" stroke-width="1" opacity="0.5"/>
  <text x="30" y="158" font-size="9" font-weight="700" fill="currentColor" stroke="none" opacity="0.7">Reading the flows</text>
  <text x="30" y="172" font-size="8.5" fill="currentColor" stroke="none" opacity="0.65">Each screen below carries a "Why" note: the framework decision or guarantee behind it — the things to know before extending the template.</text>
</svg>

## 1 · Sign up & verify

<svg viewBox="0 0 600 340" width="100%" role="img" aria-label="Sign up and verify, two screens with builder notes. Screen one, Create your account, with Email address, Password (12-character minimum) and Confirm password fields and a Create account button. Why: a soft gate with no dead end — registration redirects to a check-email screen but never blocks, and an existing email is routed to Sign in so no duplicate User is created. An arrow labelled submit leads to screen two, Confirm your email, with Resend link and Continue. Why: one step not two — the verification link confirms the email and signs the user in via after_authentication_url, and a banner nudges until verified." fill="none" stroke="currentColor" font-family="ui-sans-serif, system-ui, sans-serif">
  <defs><marker id="flowarrow-a1" markerWidth="9" markerHeight="9" refX="6.5" refY="3" orient="auto"><path d="M0,0 L8,3 L0,6 z" fill="currentColor" stroke="none"/></marker></defs>
  <rect x="20" y="30" width="250" height="185" rx="10" stroke-width="1.5"/>
  <line x1="20" y1="52" x2="270" y2="52" stroke-width="1"/>
  <circle cx="32" cy="41" r="2.5" stroke-width="1"/><circle cx="42" cy="41" r="2.5" stroke-width="1"/><circle cx="52" cy="41" r="2.5" stroke-width="1"/>
  <rect x="64" y="36" width="196" height="10" rx="5" stroke-width="1" opacity="0.5"/>
  <text x="36" y="74" font-size="11" font-weight="700" fill="currentColor" stroke="none">Create your account</text>
  <text x="36" y="92" font-size="8" fill="currentColor" stroke="none" opacity="0.7">Email address</text>
  <rect x="36" y="96" width="200" height="14" rx="4" stroke-width="1"/><text x="42" y="106" font-size="8.5" fill="currentColor" stroke="none" opacity="0.45">jane@acme.com</text>
  <text x="36" y="124" font-size="8" fill="currentColor" stroke="none" opacity="0.7">Password</text>
  <rect x="36" y="128" width="200" height="14" rx="4" stroke-width="1"/><text x="42" y="138" font-size="8.5" fill="currentColor" stroke="none" opacity="0.45">••••••••••••</text>
  <text x="36" y="153" font-size="7" fill="currentColor" stroke="none" opacity="0.5">Must be at least 12 characters.</text>
  <text x="36" y="168" font-size="8" fill="currentColor" stroke="none" opacity="0.7">Confirm password</text>
  <rect x="36" y="172" width="200" height="14" rx="4" stroke-width="1"/><text x="42" y="182" font-size="8.5" fill="currentColor" stroke="none" opacity="0.45">••••••••••••</text>
  <rect class="text-accent" x="36" y="192" width="200" height="17" rx="5" stroke-width="2.25"/><text class="text-accent" x="136" y="203.5" text-anchor="middle" font-size="9" font-weight="700" fill="currentColor" stroke="none">Create account</text>
  <rect x="330" y="30" width="250" height="150" rx="10" stroke-width="1.5"/>
  <line x1="330" y1="52" x2="580" y2="52" stroke-width="1"/>
  <circle cx="342" cy="41" r="2.5" stroke-width="1"/><circle cx="352" cy="41" r="2.5" stroke-width="1"/><circle cx="362" cy="41" r="2.5" stroke-width="1"/>
  <rect x="374" y="36" width="196" height="10" rx="5" stroke-width="1" opacity="0.5"/>
  <text x="346" y="76" font-size="11" font-weight="700" fill="currentColor" stroke="none">Confirm your email</text>
  <text x="346" y="96" font-size="8.5" fill="currentColor" stroke="none" opacity="0.65">We sent a verification link to</text>
  <text x="346" y="108" font-size="8.5" fill="currentColor" stroke="none" opacity="0.65">jane@acme.com — click to confirm.</text>
  <text x="346" y="126" font-size="8" fill="currentColor" stroke="none" opacity="0.45">The link expires in 24 hours.</text>
  <rect x="346" y="140" width="100" height="18" rx="5" stroke-width="1.25" opacity="0.8"/><text x="396" y="152.5" text-anchor="middle" font-size="9" font-weight="600" fill="currentColor" stroke="none" opacity="0.75">Resend link</text>
  <rect class="text-accent" x="456" y="140" width="100" height="18" rx="5" stroke-width="2.25"/><text class="text-accent" x="506" y="152.5" text-anchor="middle" font-size="9" font-weight="700" fill="currentColor" stroke="none">Continue</text>
  <path d="M270 110 H328" stroke-width="1.5" marker-end="url(#flowarrow-a1)"/><text x="299" y="104" text-anchor="middle" font-size="9.5" fill="currentColor" stroke="none" opacity="0.6">submit</text>
  <rect x="20" y="232" width="250" height="92" rx="5" stroke-width="1" opacity="0.5"/>
  <text x="30" y="250" font-size="9" font-weight="700" fill="currentColor" stroke="none" opacity="0.75">Why — soft gate, no dead end</text>
  <text x="30" y="265" font-size="8" fill="currentColor" stroke="none" opacity="0.65">Registration redirects to a check-email</text>
  <text x="30" y="277" font-size="8" fill="currentColor" stroke="none" opacity="0.65">screen but never blocks the user.</text>
  <text x="30" y="293" font-size="8" fill="currentColor" stroke="none" opacity="0.65">An existing email is routed to Sign in —</text>
  <text x="30" y="305" font-size="8" fill="currentColor" stroke="none" opacity="0.65">never create a duplicate User.</text>
  <rect x="330" y="232" width="250" height="92" rx="5" stroke-width="1" opacity="0.5"/>
  <text x="340" y="250" font-size="9" font-weight="700" fill="currentColor" stroke="none" opacity="0.75">Why — one step, not two</text>
  <text x="340" y="265" font-size="8" fill="currentColor" stroke="none" opacity="0.65">The verify link confirms the email AND</text>
  <text x="340" y="277" font-size="8" fill="currentColor" stroke="none" opacity="0.65">signs the user in (after_authentication_url).</text>
  <text x="340" y="293" font-size="8" fill="currentColor" stroke="none" opacity="0.65">A persistent banner nudges until verified,</text>
  <text x="340" y="305" font-size="8" fill="currentColor" stroke="none" opacity="0.65">so the gate never traps anyone.</text>
</svg>

## 2 · First-run onboarding

<svg viewBox="0 0 885 262" width="100%" role="img" aria-label="First-run onboarding, four steps with builder notes. Step one, Name your workspace. Why: posture-gated — it only runs when WORKSPACE_ON_SIGNUP is none; the RequiresOnboarding guard is html-only and early-returns otherwise. Step two, Create first project. Why: derive-from-data — onboarded_at is the only marker and the step is computed from what exists, so the wizard is resumable with no per-step flags. Step three, Pick your tools, Docs and Files. Why: self-hiding — skipped unless more than one tool is registered, a forward-only interstitial, extended in an initializer. Step four, Invite your team. Why: optional — skipping still lands a working project, finishing stamps onboarded_at, and the project home tabs follow enabled_tools." fill="none" stroke="currentColor" font-family="ui-sans-serif, system-ui, sans-serif">
  <defs><marker id="flowarrow-a2" markerWidth="9" markerHeight="9" refX="6.5" refY="3" orient="auto"><path d="M0,0 L8,3 L0,6 z" fill="currentColor" stroke="none"/></marker></defs>
  <circle cx="112" cy="28" r="9" stroke-width="1.5"/><text x="112" y="31.5" text-anchor="middle" font-size="9" font-weight="700" fill="currentColor" stroke="none">1</text>
  <rect x="20" y="40" width="185" height="110" rx="9" stroke-width="1.5"/>
  <line x1="20" y1="60" x2="205" y2="60" stroke-width="1"/>
  <circle cx="32" cy="50" r="2.5" stroke-width="1"/><circle cx="42" cy="50" r="2.5" stroke-width="1"/><circle cx="52" cy="50" r="2.5" stroke-width="1"/>
  <rect x="64" y="45" width="133" height="9" rx="4.5" stroke-width="1" opacity="0.5"/>
  <text x="34" y="78" font-size="9.5" font-weight="700" fill="currentColor" stroke="none">Name your workspace</text>
  <text x="34" y="92" font-size="7" fill="currentColor" stroke="none" opacity="0.7">Workspace name</text>
  <rect x="34" y="95" width="157" height="13" rx="4" stroke-width="1"/><text x="40" y="104.5" font-size="7.5" fill="currentColor" stroke="none" opacity="0.45">Acme Co</text>
  <rect class="text-accent" x="34" y="116" width="84" height="15" rx="5" stroke-width="2.25"/><text class="text-accent" x="76" y="126.5" text-anchor="middle" font-size="8" font-weight="700" fill="currentColor" stroke="none">Continue</text>
  <circle cx="332" cy="28" r="9" stroke-width="1.5"/><text x="332" y="31.5" text-anchor="middle" font-size="9" font-weight="700" fill="currentColor" stroke="none">2</text>
  <rect x="240" y="40" width="185" height="110" rx="9" stroke-width="1.5"/>
  <line x1="240" y1="60" x2="425" y2="60" stroke-width="1"/>
  <circle cx="252" cy="50" r="2.5" stroke-width="1"/><circle cx="262" cy="50" r="2.5" stroke-width="1"/><circle cx="272" cy="50" r="2.5" stroke-width="1"/>
  <rect x="284" y="45" width="133" height="9" rx="4.5" stroke-width="1" opacity="0.5"/>
  <text x="254" y="78" font-size="9.5" font-weight="700" fill="currentColor" stroke="none">Create first project</text>
  <text x="254" y="92" font-size="7" fill="currentColor" stroke="none" opacity="0.7">Project name</text>
  <rect x="254" y="95" width="157" height="13" rx="4" stroke-width="1"/><text x="260" y="104.5" font-size="7.5" fill="currentColor" stroke="none" opacity="0.45">Acme Website</text>
  <rect class="text-accent" x="254" y="116" width="84" height="15" rx="5" stroke-width="2.25"/><text class="text-accent" x="296" y="126.5" text-anchor="middle" font-size="8" font-weight="700" fill="currentColor" stroke="none">Continue</text>
  <circle cx="552" cy="28" r="9" stroke-width="1.5"/><text x="552" y="31.5" text-anchor="middle" font-size="9" font-weight="700" fill="currentColor" stroke="none">3</text>
  <rect x="460" y="40" width="185" height="110" rx="9" stroke-width="1.5"/>
  <line x1="460" y1="60" x2="645" y2="60" stroke-width="1"/>
  <circle cx="472" cy="50" r="2.5" stroke-width="1"/><circle cx="482" cy="50" r="2.5" stroke-width="1"/><circle cx="492" cy="50" r="2.5" stroke-width="1"/>
  <rect x="504" y="45" width="133" height="9" rx="4.5" stroke-width="1" opacity="0.5"/>
  <text x="474" y="78" font-size="9.5" font-weight="700" fill="currentColor" stroke="none">Pick your tools</text>
  <rect class="text-accent" x="474" y="90" width="11" height="11" rx="3" stroke-width="1.25"/><path class="text-accent" d="M476.5,95.5 L478.5,98 L482.5,93" stroke-width="1.5"/>
  <text x="492" y="99" font-size="8" fill="currentColor" stroke="none">Docs &amp; Files</text>
  <rect class="text-accent" x="474" y="116" width="90" height="15" rx="5" stroke-width="2.25"/><text class="text-accent" x="519" y="126.5" text-anchor="middle" font-size="8" font-weight="700" fill="currentColor" stroke="none">Save tools</text>
  <circle cx="772" cy="28" r="9" stroke-width="1.5"/><text x="772" y="31.5" text-anchor="middle" font-size="9" font-weight="700" fill="currentColor" stroke="none">4</text>
  <rect x="680" y="40" width="185" height="110" rx="9" stroke-width="1.5"/>
  <line x1="680" y1="60" x2="865" y2="60" stroke-width="1"/>
  <circle cx="692" cy="50" r="2.5" stroke-width="1"/><circle cx="702" cy="50" r="2.5" stroke-width="1"/><circle cx="712" cy="50" r="2.5" stroke-width="1"/>
  <rect x="724" y="45" width="133" height="9" rx="4.5" stroke-width="1" opacity="0.5"/>
  <text x="694" y="78" font-size="9.5" font-weight="700" fill="currentColor" stroke="none">Invite your team</text>
  <text x="694" y="92" font-size="7" fill="currentColor" stroke="none" opacity="0.7">Email addresses</text>
  <rect x="694" y="95" width="157" height="13" rx="4" stroke-width="1"/><text x="700" y="104.5" font-size="7" fill="currentColor" stroke="none" opacity="0.45">sam@example.com, lee@…</text>
  <rect class="text-accent" x="694" y="116" width="92" height="15" rx="5" stroke-width="2.25"/><text class="text-accent" x="740" y="126.5" text-anchor="middle" font-size="8" font-weight="700" fill="currentColor" stroke="none">Send invites</text>
  <path d="M205 95 H238" stroke-width="1.5" marker-end="url(#flowarrow-a2)"/><text x="221" y="89" text-anchor="middle" font-size="8" fill="currentColor" stroke="none" opacity="0.6">next</text>
  <path d="M425 95 H458" stroke-width="1.5" marker-end="url(#flowarrow-a2)"/><text x="441" y="89" text-anchor="middle" font-size="8" fill="currentColor" stroke="none" opacity="0.6">next</text>
  <path d="M645 95 H678" stroke-width="1.5" marker-end="url(#flowarrow-a2)"/><text x="661" y="89" text-anchor="middle" font-size="8" fill="currentColor" stroke="none" opacity="0.6">next</text>
  <rect x="20" y="160" width="185" height="92" rx="5" stroke-width="1" opacity="0.5"/>
  <text x="30" y="177" font-size="8.5" font-weight="700" fill="currentColor" stroke="none" opacity="0.75">Why — posture-gated</text>
  <text x="30" y="191" font-size="7.5" fill="currentColor" stroke="none" opacity="0.65">Only runs when WORKSPACE_ON_SIGNUP</text>
  <text x="30" y="202" font-size="7.5" fill="currentColor" stroke="none" opacity="0.65">= none. The RequiresOnboarding guard is</text>
  <text x="30" y="213" font-size="7.5" fill="currentColor" stroke="none" opacity="0.65">html-only and early-returns otherwise.</text>
  <rect x="240" y="160" width="185" height="92" rx="5" stroke-width="1" opacity="0.5"/>
  <text x="250" y="177" font-size="8.5" font-weight="700" fill="currentColor" stroke="none" opacity="0.75">Why — derive-from-data</text>
  <text x="250" y="191" font-size="7.5" fill="currentColor" stroke="none" opacity="0.65">onboarded_at is the only marker; the step</text>
  <text x="250" y="202" font-size="7.5" fill="currentColor" stroke="none" opacity="0.65">is computed from what exists, so the</text>
  <text x="250" y="213" font-size="7.5" fill="currentColor" stroke="none" opacity="0.65">wizard is resumable — no per-step flags.</text>
  <rect x="460" y="160" width="185" height="92" rx="5" stroke-width="1" opacity="0.5"/>
  <text x="470" y="177" font-size="8.5" font-weight="700" fill="currentColor" stroke="none" opacity="0.75">Why — self-hiding</text>
  <text x="470" y="191" font-size="7.5" fill="currentColor" stroke="none" opacity="0.65">Skipped unless &gt;1 tool is registered —</text>
  <text x="470" y="202" font-size="7.5" fill="currentColor" stroke="none" opacity="0.65">never a one-option screen. Forward-only.</text>
  <text x="470" y="213" font-size="7.5" fill="currentColor" stroke="none" opacity="0.65">Add tools in an initializer.</text>
  <rect x="680" y="160" width="185" height="92" rx="5" stroke-width="1" opacity="0.5"/>
  <text x="690" y="177" font-size="8.5" font-weight="700" fill="currentColor" stroke="none" opacity="0.75">Why — optional</text>
  <text x="690" y="191" font-size="7.5" fill="currentColor" stroke="none" opacity="0.65">Skipping still lands a working project;</text>
  <text x="690" y="202" font-size="7.5" fill="currentColor" stroke="none" opacity="0.65">finishing stamps onboarded_at. The home</text>
  <text x="690" y="213" font-size="7.5" fill="currentColor" stroke="none" opacity="0.65">tabs follow the project's enabled_tools.</text>
</svg>

## 3 · Project home & tools

<svg viewBox="0 0 600 290" width="100%" role="img" aria-label="Project home and tools, two screens with builder notes. Screen one, the project home for Acme Website with an active Docs and Files tab and a Project tools settings entry. Why: the tab bar reads projects.enabled_tools JSON, not a hardcoded list, so forks add tools without touching the view. An arrow labelled settings leads to screen two, Project tools settings with a checked Docs and Files option. Why: a registry seam — toggling writes enabled_tools; register tools in config slash initializers slash project_tools.rb and gate a controller with the EnforcesProjectTool concern." fill="none" stroke="currentColor" font-family="ui-sans-serif, system-ui, sans-serif">
  <defs><marker id="flowarrow-a3" markerWidth="9" markerHeight="9" refX="6.5" refY="3" orient="auto"><path d="M0,0 L8,3 L0,6 z" fill="currentColor" stroke="none"/></marker></defs>
  <rect x="20" y="40" width="250" height="150" rx="10" stroke-width="1.5"/>
  <line x1="20" y1="62" x2="270" y2="62" stroke-width="1"/>
  <circle cx="32" cy="51" r="2.5" stroke-width="1"/><circle cx="42" cy="51" r="2.5" stroke-width="1"/><circle cx="52" cy="51" r="2.5" stroke-width="1"/>
  <rect x="64" y="46" width="196" height="11" rx="5" stroke-width="1" opacity="0.5"/>
  <text x="36" y="80" font-size="7" fill="currentColor" stroke="none" opacity="0.5">Acme Co</text>
  <text x="36" y="94" font-size="11" font-weight="700" fill="currentColor" stroke="none">Acme Website</text>
  <rect class="text-accent" x="36" y="102" width="80" height="15" rx="4" stroke-width="2"/><text class="text-accent" x="76" y="112.5" text-anchor="middle" font-size="7.5" font-weight="700" fill="currentColor" stroke="none">Docs &amp; Files</text>
  <text x="124" y="113" font-size="8" fill="currentColor" stroke="none" opacity="0.55">Project tools</text>
  <rect x="36" y="130" width="200" height="6" rx="3" fill="currentColor" stroke="none" opacity="0.16"/>
  <rect x="36" y="142" width="160" height="6" rx="3" fill="currentColor" stroke="none" opacity="0.16"/>
  <rect x="36" y="154" width="180" height="6" rx="3" fill="currentColor" stroke="none" opacity="0.16"/>
  <rect x="330" y="40" width="250" height="150" rx="10" stroke-width="1.5"/>
  <line x1="330" y1="62" x2="580" y2="62" stroke-width="1"/>
  <circle cx="342" cy="51" r="2.5" stroke-width="1"/><circle cx="352" cy="51" r="2.5" stroke-width="1"/><circle cx="362" cy="51" r="2.5" stroke-width="1"/>
  <rect x="374" y="46" width="196" height="11" rx="5" stroke-width="1" opacity="0.5"/>
  <text x="346" y="82" font-size="11" font-weight="700" fill="currentColor" stroke="none">Project tools</text>
  <text x="346" y="96" font-size="7.5" fill="currentColor" stroke="none" opacity="0.6">Choose which tools this project uses.</text>
  <rect class="text-accent" x="346" y="106" width="11" height="11" rx="3" stroke-width="1.25"/><path class="text-accent" d="M348.5,111.5 L350.5,114 L354.5,109" stroke-width="1.5"/>
  <text x="363" y="115" font-size="8.5" fill="currentColor" stroke="none">Docs &amp; Files</text>
  <text x="363" y="127" font-size="7" fill="currentColor" stroke="none" opacity="0.5">Documents and files for this project.</text>
  <rect class="text-accent" x="346" y="140" width="90" height="16" rx="5" stroke-width="2.25"/><text class="text-accent" x="391" y="151" text-anchor="middle" font-size="8.5" font-weight="700" fill="currentColor" stroke="none">Save tools</text>
  <path d="M270 115 H328" stroke-width="1.5" marker-end="url(#flowarrow-a3)"/><text x="299" y="109" text-anchor="middle" font-size="9" fill="currentColor" stroke="none" opacity="0.6">settings</text>
  <rect x="20" y="205" width="250" height="78" rx="5" stroke-width="1" opacity="0.5"/>
  <text x="30" y="221" font-size="8.5" font-weight="700" fill="currentColor" stroke="none" opacity="0.75">Why — tabs follow the data</text>
  <text x="30" y="235" font-size="7.5" fill="currentColor" stroke="none" opacity="0.65">The tab bar reads projects.enabled_tools</text>
  <text x="30" y="247" font-size="7.5" fill="currentColor" stroke="none" opacity="0.65">(JSON), not a hardcoded list — so forks</text>
  <text x="30" y="259" font-size="7.5" fill="currentColor" stroke="none" opacity="0.65">add tools without touching the view.</text>
  <rect x="330" y="205" width="250" height="78" rx="5" stroke-width="1" opacity="0.5"/>
  <text x="340" y="221" font-size="8.5" font-weight="700" fill="currentColor" stroke="none" opacity="0.75">Why — a registry seam</text>
  <text x="340" y="235" font-size="7.5" fill="currentColor" stroke="none" opacity="0.65">Toggling writes enabled_tools. Register</text>
  <text x="340" y="247" font-size="7.5" fill="currentColor" stroke="none" opacity="0.65">tools in config/initializers/project_tools.rb;</text>
  <text x="340" y="259" font-size="7.5" fill="currentColor" stroke="none" opacity="0.65">gate a controller with EnforcesProjectTool.</text>
</svg>

## 4 · Invite teammates

<svg viewBox="0 0 645 305" width="100%" role="img" aria-label="Inviting teammates, three screens with builder notes. Screen one, Invite members, an Email addresses field with a Member role and Send invitations. Why: role is set at invite time and is per-workspace with JSON permissions; only manage_members users can invite via Pundit; a shareable magic link is the alternative. A dashed arrow labelled sent leads to the invitation email, Jamie invited you to join Acme Co as a Member, with Accept invitation and Decline. Why: the invite carries the recipient email so the bearer link isn't a free-for-all. An arrow labelled accept leads to Set up your login. Why: consume-before-verify with an EmailMismatch guard means a leaked link can't be claimed by another address; existing users join in one click, new emails set up a login." fill="none" stroke="currentColor" font-family="ui-sans-serif, system-ui, sans-serif">
  <defs><marker id="flowarrow-a4" markerWidth="9" markerHeight="9" refX="6.5" refY="3" orient="auto"><path d="M0,0 L8,3 L0,6 z" fill="currentColor" stroke="none"/></marker></defs>
  <rect x="20" y="40" width="185" height="150" rx="9" stroke-width="1.5"/>
  <line x1="20" y1="60" x2="205" y2="60" stroke-width="1"/>
  <circle cx="32" cy="50" r="2.5" stroke-width="1"/><circle cx="42" cy="50" r="2.5" stroke-width="1"/><circle cx="52" cy="50" r="2.5" stroke-width="1"/>
  <rect x="64" y="45" width="133" height="9" rx="4.5" stroke-width="1" opacity="0.5"/>
  <text x="34" y="78" font-size="10" font-weight="700" fill="currentColor" stroke="none">Invite members</text>
  <text x="34" y="92" font-size="7" fill="currentColor" stroke="none" opacity="0.7">Email addresses</text>
  <rect x="34" y="95" width="157" height="13" rx="4" stroke-width="1"/><text x="40" y="104.5" font-size="7" fill="currentColor" stroke="none" opacity="0.45">sam@acme.com, lee@acme.com</text>
  <text x="34" y="122" font-size="7" fill="currentColor" stroke="none" opacity="0.7">Role</text>
  <rect x="58" y="114" width="56" height="12" rx="3" stroke-width="1" opacity="0.7"/><text x="86" y="122.5" text-anchor="middle" font-size="7.5" fill="currentColor" stroke="none" opacity="0.8">Member ▾</text>
  <rect class="text-accent" x="34" y="134" width="112" height="15" rx="5" stroke-width="2.25"/><text class="text-accent" x="90" y="144.5" text-anchor="middle" font-size="8" font-weight="700" fill="currentColor" stroke="none">Send invitations</text>
  <rect x="240" y="40" width="185" height="150" rx="9" stroke-width="1.5"/>
  <line x1="240" y1="60" x2="425" y2="60" stroke-width="1"/>
  <circle cx="252" cy="50" r="2.5" stroke-width="1"/><circle cx="262" cy="50" r="2.5" stroke-width="1"/><circle cx="272" cy="50" r="2.5" stroke-width="1"/>
  <rect x="284" y="45" width="133" height="9" rx="4.5" stroke-width="1" opacity="0.5"/>
  <text x="254" y="78" font-size="9.5" font-weight="700" fill="currentColor" stroke="none">You've been invited</text>
  <text x="254" y="94" font-size="7.5" fill="currentColor" stroke="none" opacity="0.65">Jamie invited you to join</text>
  <text x="254" y="104" font-size="7.5" fill="currentColor" stroke="none" opacity="0.65">Acme Co as a Member.</text>
  <rect class="text-accent" x="254" y="114" width="120" height="15" rx="5" stroke-width="2.25"/><text class="text-accent" x="314" y="124.5" text-anchor="middle" font-size="8" font-weight="700" fill="currentColor" stroke="none">Accept invitation</text>
  <rect x="254" y="134" width="64" height="13" rx="5" stroke-width="1.25" opacity="0.8"/><text x="286" y="143" text-anchor="middle" font-size="7.5" font-weight="600" fill="currentColor" stroke="none" opacity="0.75">Decline</text>
  <text x="254" y="162" font-size="6.5" fill="currentColor" stroke="none" opacity="0.5">This invitation expires in 7 days.</text>
  <rect x="460" y="40" width="185" height="150" rx="9" stroke-width="1.5"/>
  <line x1="460" y1="60" x2="645" y2="60" stroke-width="1"/>
  <circle cx="472" cy="50" r="2.5" stroke-width="1"/><circle cx="482" cy="50" r="2.5" stroke-width="1"/><circle cx="492" cy="50" r="2.5" stroke-width="1"/>
  <rect x="504" y="45" width="133" height="9" rx="4.5" stroke-width="1" opacity="0.5"/>
  <text x="474" y="78" font-size="10" font-weight="700" fill="currentColor" stroke="none">Set up your login</text>
  <text x="474" y="92" font-size="7" fill="currentColor" stroke="none" opacity="0.7">First name</text>
  <rect x="474" y="95" width="157" height="13" rx="4" stroke-width="1"/><text x="480" y="104.5" font-size="7.5" fill="currentColor" stroke="none" opacity="0.45">Sam Diaz</text>
  <text x="474" y="121" font-size="7" fill="currentColor" stroke="none" opacity="0.7">Create password</text>
  <rect x="474" y="124" width="157" height="13" rx="4" stroke-width="1"/><text x="480" y="133.5" font-size="7.5" fill="currentColor" stroke="none" opacity="0.45">••••••••••••</text>
  <rect class="text-accent" x="474" y="144" width="104" height="15" rx="5" stroke-width="2.25"/><text class="text-accent" x="526" y="154.5" text-anchor="middle" font-size="8" font-weight="700" fill="currentColor" stroke="none">Join Acme Co</text>
  <path d="M205 95 H238" stroke-width="1.5" stroke-dasharray="6 4" opacity="0.6" marker-end="url(#flowarrow-a4)"/><text x="221" y="89" text-anchor="middle" font-size="8" fill="currentColor" stroke="none" opacity="0.6">sent</text>
  <path d="M425 95 H458" stroke-width="1.5" marker-end="url(#flowarrow-a4)"/><text x="441" y="89" text-anchor="middle" font-size="8" fill="currentColor" stroke="none" opacity="0.6">accept</text>
  <rect x="20" y="205" width="185" height="92" rx="5" stroke-width="1" opacity="0.5"/>
  <text x="30" y="221" font-size="8.5" font-weight="700" fill="currentColor" stroke="none" opacity="0.75">Why — role at invite time</text>
  <text x="30" y="235" font-size="7.5" fill="currentColor" stroke="none" opacity="0.65">Role is per-workspace (JSON perms).</text>
  <text x="30" y="246" font-size="7.5" fill="currentColor" stroke="none" opacity="0.65">Only manage_members users invite (Pundit).</text>
  <text x="30" y="257" font-size="7.5" fill="currentColor" stroke="none" opacity="0.65">A shareable magic link is the alternative.</text>
  <rect x="240" y="205" width="185" height="92" rx="5" stroke-width="1" opacity="0.5"/>
  <text x="250" y="221" font-size="8.5" font-weight="700" fill="currentColor" stroke="none" opacity="0.75">Why — a scoped link</text>
  <text x="250" y="235" font-size="7.5" fill="currentColor" stroke="none" opacity="0.65">The invite carries the recipient email,</text>
  <text x="250" y="246" font-size="7.5" fill="currentColor" stroke="none" opacity="0.65">so the bearer link isn't a free-for-all.</text>
  <rect x="460" y="205" width="185" height="92" rx="5" stroke-width="1" opacity="0.5"/>
  <text x="470" y="221" font-size="8.5" font-weight="700" fill="currentColor" stroke="none" opacity="0.75">Why — consume-before-verify</text>
  <text x="470" y="235" font-size="7.5" fill="currentColor" stroke="none" opacity="0.65">EmailMismatch guard: a leaked link can't</text>
  <text x="470" y="246" font-size="7.5" fill="currentColor" stroke="none" opacity="0.65">be claimed by another address. Existing</text>
  <text x="470" y="257" font-size="7.5" fill="currentColor" stroke="none" opacity="0.65">user → one-click; new email → set up login.</text>
</svg>

## 5 · Clientside

<svg viewBox="0 0 885 305" width="100%" role="img" aria-label="Clientside, four screens with builder notes. Screen one, Client access, a toggle Turn on Clientside and Save. Why: opt-in per project via clientside_enabled, off by default. Screen two, Edit document, a checked Share with the client side. Why: client_visible? equals shared_with_client AND published, so a shared draft never leaks. Screen three, Invite a client, with Client email and Their company and Send client invite. Why: it reuses the hardened Invitation accept and consume path but creates a ClientAccess, not a Membership, with the same EmailMismatch protection. Screen four, the accent-highlighted client area, Acme Co Client area, Shared with you, read-only items. Why: ClientAccess is a separate axis — no seat, never in Pundit workspace policies, the area never sets Current.workspace, and it shows only shared and published items." fill="none" stroke="currentColor" font-family="ui-sans-serif, system-ui, sans-serif">
  <defs><marker id="flowarrow-a5" markerWidth="9" markerHeight="9" refX="6.5" refY="3" orient="auto"><path d="M0,0 L8,3 L0,6 z" fill="currentColor" stroke="none"/></marker></defs>
  <rect x="20" y="40" width="185" height="150" rx="9" stroke-width="1.5"/>
  <line x1="20" y1="60" x2="205" y2="60" stroke-width="1"/>
  <circle cx="32" cy="50" r="2.5" stroke-width="1"/><circle cx="42" cy="50" r="2.5" stroke-width="1"/><circle cx="52" cy="50" r="2.5" stroke-width="1"/>
  <rect x="64" y="45" width="133" height="9" rx="4.5" stroke-width="1" opacity="0.5"/>
  <text x="34" y="78" font-size="10" font-weight="700" fill="currentColor" stroke="none">Client access</text>
  <rect class="text-accent" x="34" y="92" width="24" height="12" rx="6" stroke-width="1.25"/><circle class="text-accent" cx="52" cy="98" r="4" fill="currentColor" stroke="none"/>
  <text x="64" y="101" font-size="7.5" fill="currentColor" stroke="none">Turn on Clientside</text>
  <rect class="text-accent" x="34" y="118" width="60" height="15" rx="5" stroke-width="2.25"/><text class="text-accent" x="64" y="128.5" text-anchor="middle" font-size="8" font-weight="700" fill="currentColor" stroke="none">Save</text>
  <rect x="240" y="40" width="185" height="150" rx="9" stroke-width="1.5"/>
  <line x1="240" y1="60" x2="425" y2="60" stroke-width="1"/>
  <circle cx="252" cy="50" r="2.5" stroke-width="1"/><circle cx="262" cy="50" r="2.5" stroke-width="1"/><circle cx="272" cy="50" r="2.5" stroke-width="1"/>
  <rect x="284" y="45" width="133" height="9" rx="4.5" stroke-width="1" opacity="0.5"/>
  <text x="254" y="78" font-size="10" font-weight="700" fill="currentColor" stroke="none">Edit document</text>
  <rect class="text-accent" x="254" y="91" width="11" height="11" rx="3" stroke-width="1.25"/><path class="text-accent" d="M256.5,96.5 L258.5,99 L262.5,94" stroke-width="1.5"/>
  <text x="271" y="100" font-size="7.5" fill="currentColor" stroke="none">Share with the client side</text>
  <text x="271" y="112" font-size="6.5" fill="currentColor" stroke="none" opacity="0.5">shown only when Clientside is on</text>
  <rect class="text-accent" x="254" y="122" width="60" height="15" rx="5" stroke-width="2.25"/><text class="text-accent" x="284" y="132.5" text-anchor="middle" font-size="8" font-weight="700" fill="currentColor" stroke="none">Save</text>
  <rect x="460" y="40" width="185" height="150" rx="9" stroke-width="1.5"/>
  <line x1="460" y1="60" x2="645" y2="60" stroke-width="1"/>
  <circle cx="472" cy="50" r="2.5" stroke-width="1"/><circle cx="482" cy="50" r="2.5" stroke-width="1"/><circle cx="492" cy="50" r="2.5" stroke-width="1"/>
  <rect x="504" y="45" width="133" height="9" rx="4.5" stroke-width="1" opacity="0.5"/>
  <text x="474" y="78" font-size="10" font-weight="700" fill="currentColor" stroke="none">Invite a client</text>
  <text x="474" y="91" font-size="7" fill="currentColor" stroke="none" opacity="0.7">Client email</text>
  <rect x="474" y="94" width="157" height="13" rx="4" stroke-width="1"/><text x="480" y="103.5" font-size="7.5" fill="currentColor" stroke="none" opacity="0.45">dana@bigco.com</text>
  <text x="474" y="120" font-size="7" fill="currentColor" stroke="none" opacity="0.7">Their company</text>
  <rect x="474" y="123" width="157" height="13" rx="4" stroke-width="1"/><text x="480" y="132.5" font-size="7.5" fill="currentColor" stroke="none" opacity="0.45">BigCo</text>
  <rect class="text-accent" x="474" y="144" width="130" height="15" rx="5" stroke-width="2.25"/><text class="text-accent" x="539" y="154.5" text-anchor="middle" font-size="8" font-weight="700" fill="currentColor" stroke="none">Send client invite</text>
  <rect class="text-accent" x="680" y="40" width="185" height="150" rx="9" stroke-width="2"/>
  <line x1="680" y1="60" x2="865" y2="60" stroke-width="1"/>
  <circle cx="692" cy="50" r="2.5" stroke-width="1"/><circle cx="702" cy="50" r="2.5" stroke-width="1"/><circle cx="712" cy="50" r="2.5" stroke-width="1"/>
  <rect x="724" y="45" width="133" height="9" rx="4.5" stroke-width="1" opacity="0.5"/>
  <text x="694" y="78" font-size="9" font-weight="700" fill="currentColor" stroke="none">Acme Co · Client area</text>
  <text x="694" y="93" font-size="7.5" fill="currentColor" stroke="none" opacity="0.7">Shared with you</text>
  <rect x="694" y="103" width="150" height="6" rx="3" fill="currentColor" stroke="none" opacity="0.16"/>
  <rect x="694" y="114" width="130" height="6" rx="3" fill="currentColor" stroke="none" opacity="0.16"/>
  <rect x="694" y="125" width="140" height="6" rx="3" fill="currentColor" stroke="none" opacity="0.16"/>
  <path d="M205 95 H238" stroke-width="1.5" marker-end="url(#flowarrow-a5)"/><text x="221" y="89" text-anchor="middle" font-size="8" fill="currentColor" stroke="none" opacity="0.6">share</text>
  <path d="M425 95 H458" stroke-width="1.5" marker-end="url(#flowarrow-a5)"/><text x="441" y="89" text-anchor="middle" font-size="8" fill="currentColor" stroke="none" opacity="0.6">invite</text>
  <path d="M645 95 H678" stroke-width="1.5" stroke-dasharray="6 4" opacity="0.6" marker-end="url(#flowarrow-a5)"/><text x="661" y="89" text-anchor="middle" font-size="8" fill="currentColor" stroke="none" opacity="0.6">accept</text>
  <rect x="20" y="205" width="185" height="92" rx="5" stroke-width="1" opacity="0.5"/>
  <text x="30" y="221" font-size="8.5" font-weight="700" fill="currentColor" stroke="none" opacity="0.75">Why — opt-in per project</text>
  <text x="30" y="235" font-size="7.5" fill="currentColor" stroke="none" opacity="0.65">clientside_enabled toggle, off by</text>
  <text x="30" y="246" font-size="7.5" fill="currentColor" stroke="none" opacity="0.65">default. Nothing leaks until you opt in.</text>
  <rect x="240" y="205" width="185" height="92" rx="5" stroke-width="1" opacity="0.5"/>
  <text x="250" y="221" font-size="8.5" font-weight="700" fill="currentColor" stroke="none" opacity="0.75">Why — published is the gate</text>
  <text x="250" y="235" font-size="7.5" fill="currentColor" stroke="none" opacity="0.65">client_visible? = shared_with_client AND</text>
  <text x="250" y="246" font-size="7.5" fill="currentColor" stroke="none" opacity="0.65">published — a shared draft never leaks.</text>
  <rect x="460" y="205" width="185" height="92" rx="5" stroke-width="1" opacity="0.5"/>
  <text x="470" y="221" font-size="8.5" font-weight="700" fill="currentColor" stroke="none" opacity="0.75">Why — reuse the hardened path</text>
  <text x="470" y="235" font-size="7.5" fill="currentColor" stroke="none" opacity="0.65">Creates a ClientAccess, not a Membership,</text>
  <text x="470" y="246" font-size="7.5" fill="currentColor" stroke="none" opacity="0.65">via the same accept!/consume! + guard.</text>
  <rect x="680" y="205" width="185" height="92" rx="5" stroke-width="1" opacity="0.5"/>
  <text x="690" y="221" font-size="8.5" font-weight="700" fill="currentColor" stroke="none" opacity="0.75">Why — a separate axis</text>
  <text x="690" y="235" font-size="7.5" fill="currentColor" stroke="none" opacity="0.65">No seat, never in Pundit workspace</text>
  <text x="690" y="246" font-size="7.5" fill="currentColor" stroke="none" opacity="0.65">policies; the area never sets</text>
  <text x="690" y="257" font-size="7.5" fill="currentColor" stroke="none" opacity="0.65">Current.workspace. Shared+published only.</text>
</svg>
