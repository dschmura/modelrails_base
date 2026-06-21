---
title: Application Flows (detailed)
description: High-fidelity wireframes of every current user journey — real field labels, example values, button copy, role keys, and annotated edge cases. The detailed alternate to the low-fi Application Flows.
keywords: wireframes flows journeys onboarding signup verify project tools invite teammates members clientside client fields labels detailed
audience: [guide, technical]
---

# Application Flows (detailed)

A higher-fidelity take on the [Application Flows](/docs/application-flows) wireframes: every screen shows the **real field labels, example values, and button copy** from the app, plus sticky-note annotations calling out edge cases and the keys behind each step. Same five journeys, drawn in the docs' theme-adaptive style. These show information architecture and copy, not final visual design.

## Legend

- **Labeled field** = a real form field — its label above a box holding an example value.
- **Bold outline** = primary action (real button copy) · **thin outline** = secondary action.
- **Accent** = the emphasized or "after" state (toggle on, active tab, final screen).
- **Pill** = a role or tag · **Note** (faint box) = an edge case, branch, or the key behind the step.

## 1 · Sign up & verify

Self-serve registration, then a soft, non-blocking email gate. See: [Email & verification](/docs/emails), [Accounts](/docs/accounts).

<svg viewBox="0 0 600 345" width="100%" role="img" aria-label="Sign up and verify, two screens. Screen one, Create your account, with Email address (jane@acme.com), Password (twelve-character minimum), and Confirm password fields, a Create account button, and an Already have an account? Sign in link. An arrow labelled submit leads to screen two, Confirm your email, which says a verification link was sent to jane@acme.com, with Resend link and Continue buttons. Notes: a non-blocking Please confirm your email address banner persists until verified; the verify link signs the user in and starts onboarding; an existing email is routed to Sign in; magic-link signup is passwordless and collects first and last name instead." fill="none" stroke="currentColor" font-family="ui-sans-serif, system-ui, sans-serif">
  <defs><marker id="flowarrow-d1" markerWidth="9" markerHeight="9" refX="6.5" refY="3" orient="auto"><path d="M0,0 L8,3 L0,6 z" fill="currentColor" stroke="none"/></marker></defs>
  <rect x="20" y="40" width="250" height="200" rx="10" stroke-width="1.5"/>
  <line x1="20" y1="62" x2="270" y2="62" stroke-width="1"/>
  <circle cx="32" cy="51" r="2.5" stroke-width="1"/><circle cx="42" cy="51" r="2.5" stroke-width="1"/><circle cx="52" cy="51" r="2.5" stroke-width="1"/>
  <rect x="64" y="46" width="196" height="11" rx="5" stroke-width="1" opacity="0.5"/>
  <text x="36" y="84" font-size="11" font-weight="700" fill="currentColor" stroke="none">Create your account</text>
  <text x="36" y="102" font-size="8" fill="currentColor" stroke="none" opacity="0.7">Email address</text>
  <rect x="36" y="106" width="200" height="15" rx="4" stroke-width="1"/><text x="42" y="116" font-size="8.5" fill="currentColor" stroke="none" opacity="0.45">jane@acme.com</text>
  <text x="36" y="136" font-size="8" fill="currentColor" stroke="none" opacity="0.7">Password</text>
  <rect x="36" y="140" width="200" height="15" rx="4" stroke-width="1"/><text x="42" y="150" font-size="8.5" fill="currentColor" stroke="none" opacity="0.45">••••••••••••</text>
  <text x="36" y="167" font-size="7" fill="currentColor" stroke="none" opacity="0.5">Must be at least 12 characters.</text>
  <text x="36" y="183" font-size="8" fill="currentColor" stroke="none" opacity="0.7">Confirm password</text>
  <rect x="36" y="187" width="200" height="15" rx="4" stroke-width="1"/><text x="42" y="197" font-size="8.5" fill="currentColor" stroke="none" opacity="0.45">••••••••••••</text>
  <rect class="text-accent" x="36" y="209" width="200" height="18" rx="5" stroke-width="2.25"/><text class="text-accent" x="136" y="221.5" text-anchor="middle" font-size="9" font-weight="700" fill="currentColor" stroke="none">Create account</text>
  <text x="36" y="237" font-size="7.5" fill="currentColor" stroke="none" opacity="0.6">Already have an account? Sign in</text>
  <rect x="330" y="40" width="250" height="170" rx="10" stroke-width="1.5"/>
  <line x1="330" y1="62" x2="580" y2="62" stroke-width="1"/>
  <circle cx="342" cy="51" r="2.5" stroke-width="1"/><circle cx="352" cy="51" r="2.5" stroke-width="1"/><circle cx="362" cy="51" r="2.5" stroke-width="1"/>
  <rect x="374" y="46" width="196" height="11" rx="5" stroke-width="1" opacity="0.5"/>
  <text x="346" y="86" font-size="11" font-weight="700" fill="currentColor" stroke="none">Confirm your email</text>
  <text x="346" y="106" font-size="8.5" fill="currentColor" stroke="none" opacity="0.65">We sent a verification link to</text>
  <text x="346" y="118" font-size="8.5" fill="currentColor" stroke="none" opacity="0.65">jane@acme.com — click to confirm.</text>
  <text x="346" y="136" font-size="8" fill="currentColor" stroke="none" opacity="0.45">The link expires in 24 hours.</text>
  <rect x="346" y="150" width="100" height="18" rx="5" stroke-width="1.25" opacity="0.8"/><text x="396" y="162.5" text-anchor="middle" font-size="9" font-weight="600" fill="currentColor" stroke="none" opacity="0.75">Resend link</text>
  <rect class="text-accent" x="456" y="150" width="100" height="18" rx="5" stroke-width="2.25"/><text class="text-accent" x="506" y="162.5" text-anchor="middle" font-size="9" font-weight="700" fill="currentColor" stroke="none">Continue</text>
  <path d="M270 120 H328" stroke-width="1.5" marker-end="url(#flowarrow-d1)"/><text x="299" y="114" text-anchor="middle" font-size="9.5" fill="currentColor" stroke="none" opacity="0.6">submit</text>
  <text x="145" y="258" text-anchor="middle" font-size="10" fill="currentColor" stroke="none">Create your account</text>
  <text x="455" y="228" text-anchor="middle" font-size="10" fill="currentColor" stroke="none">Check your email</text>
  <text x="455" y="241" text-anchor="middle" font-size="9" fill="currentColor" stroke="none" opacity="0.55">soft gate · non-blocking</text>
  <rect x="20" y="278" width="560" height="52" rx="5" stroke-width="1" opacity="0.5"/>
  <text x="30" y="293" font-size="9" font-weight="700" fill="currentColor" stroke="none" opacity="0.7">Notes</text>
  <text x="30" y="305" font-size="8.5" fill="currentColor" stroke="none" opacity="0.65">A "Please confirm your email address." banner persists until verified — it never blocks. Verify link signs the user in → onboarding.</text>
  <text x="30" y="318" font-size="8.5" fill="currentColor" stroke="none" opacity="0.65">Existing email → routed to Sign in (no duplicate). Magic-link signup is passwordless: collects First name + Last name instead.</text>
</svg>

## 2 · First-run onboarding

Under the `none` posture, a new user's first session is a short, resumable wizard. See: [Onboarding](/docs/onboarding).

<svg viewBox="0 0 820 460" width="100%" role="img" aria-label="First-run onboarding, four numbered steps then the project home. Step one, Name your workspace, field Workspace name (Acme Co), Continue. Step two, Create your first project, fields Project name (Acme Website) and What's it about optional, Continue. Step three, Pick your tools, a checklist with Docs and Files enabled, Save tools; this step self-hides unless more than one tool is registered. A connector labelled first project saved drops to step four, Invite your team, an Email addresses field with a Member role, Send invites or Skip. The final screen is the project home, accent-highlighted, with an active Docs and Files tab." fill="none" stroke="currentColor" font-family="ui-sans-serif, system-ui, sans-serif">
  <defs><marker id="flowarrow-d2" markerWidth="9" markerHeight="9" refX="6.5" refY="3" orient="auto"><path d="M0,0 L8,3 L0,6 z" fill="currentColor" stroke="none"/></marker></defs>
  <circle cx="135" cy="38" r="10" stroke-width="1.5"/><text x="135" y="42" text-anchor="middle" font-size="10" font-weight="700" fill="currentColor" stroke="none">1</text>
  <rect x="20" y="50" width="230" height="150" rx="10" stroke-width="1.5"/>
  <line x1="20" y1="72" x2="250" y2="72" stroke-width="1"/>
  <circle cx="32" cy="61" r="2.5" stroke-width="1"/><circle cx="42" cy="61" r="2.5" stroke-width="1"/><circle cx="52" cy="61" r="2.5" stroke-width="1"/>
  <rect x="64" y="56" width="176" height="10" rx="5" stroke-width="1" opacity="0.5"/>
  <text x="34" y="92" font-size="10" font-weight="700" fill="currentColor" stroke="none">Name your workspace</text>
  <text x="34" y="105" font-size="7.5" fill="currentColor" stroke="none" opacity="0.6">This is the workspace your team will join.</text>
  <text x="34" y="124" font-size="7.5" fill="currentColor" stroke="none" opacity="0.7">Workspace name</text>
  <rect x="34" y="128" width="182" height="15" rx="4" stroke-width="1"/><text x="40" y="138" font-size="8.5" fill="currentColor" stroke="none" opacity="0.45">Acme Co</text>
  <rect class="text-accent" x="34" y="156" width="100" height="17" rx="5" stroke-width="2.25"/><text class="text-accent" x="84" y="168" text-anchor="middle" font-size="9" font-weight="700" fill="currentColor" stroke="none">Continue</text>
  <circle cx="405" cy="38" r="10" stroke-width="1.5"/><text x="405" y="42" text-anchor="middle" font-size="10" font-weight="700" fill="currentColor" stroke="none">2</text>
  <rect x="290" y="50" width="230" height="150" rx="10" stroke-width="1.5"/>
  <line x1="290" y1="72" x2="520" y2="72" stroke-width="1"/>
  <circle cx="302" cy="61" r="2.5" stroke-width="1"/><circle cx="312" cy="61" r="2.5" stroke-width="1"/><circle cx="322" cy="61" r="2.5" stroke-width="1"/>
  <rect x="334" y="56" width="176" height="10" rx="5" stroke-width="1" opacity="0.5"/>
  <text x="304" y="92" font-size="10" font-weight="700" fill="currentColor" stroke="none">Create your first project</text>
  <text x="304" y="105" font-size="7.5" fill="currentColor" stroke="none" opacity="0.6">Projects hold the work — add more later.</text>
  <text x="304" y="122" font-size="7.5" fill="currentColor" stroke="none" opacity="0.7">Project name</text>
  <rect x="304" y="126" width="182" height="14" rx="4" stroke-width="1"/><text x="310" y="136" font-size="8.5" fill="currentColor" stroke="none" opacity="0.45">Acme Website</text>
  <text x="304" y="152" font-size="7.5" fill="currentColor" stroke="none" opacity="0.7">What's it about? (optional)</text>
  <rect x="304" y="156" width="182" height="14" rx="4" stroke-width="1"/>
  <rect class="text-accent" x="304" y="176" width="100" height="17" rx="5" stroke-width="2.25"/><text class="text-accent" x="354" y="188" text-anchor="middle" font-size="9" font-weight="700" fill="currentColor" stroke="none">Continue</text>
  <circle cx="675" cy="38" r="10" stroke-width="1.5"/><text x="675" y="42" text-anchor="middle" font-size="10" font-weight="700" fill="currentColor" stroke="none">3</text>
  <rect x="560" y="50" width="230" height="150" rx="10" stroke-width="1.5"/>
  <line x1="560" y1="72" x2="790" y2="72" stroke-width="1"/>
  <circle cx="572" cy="61" r="2.5" stroke-width="1"/><circle cx="582" cy="61" r="2.5" stroke-width="1"/><circle cx="592" cy="61" r="2.5" stroke-width="1"/>
  <rect x="604" y="56" width="176" height="10" rx="5" stroke-width="1" opacity="0.5"/>
  <text x="574" y="92" font-size="10" font-weight="700" fill="currentColor" stroke="none">Pick your tools</text>
  <text x="574" y="105" font-size="7.5" fill="currentColor" stroke="none" opacity="0.6">Turn on the tools this project needs.</text>
  <rect class="text-accent" x="574" y="120" width="11" height="11" rx="3" stroke-width="1.25"/><path class="text-accent" d="M576.5,125.5 L578.5,128 L582.5,123" stroke-width="1.5"/>
  <text x="592" y="129" font-size="8.5" fill="currentColor" stroke="none">Docs &amp; Files</text>
  <rect class="text-accent" x="574" y="156" width="100" height="17" rx="5" stroke-width="2.25"/><text class="text-accent" x="624" y="168" text-anchor="middle" font-size="9" font-weight="700" fill="currentColor" stroke="none">Save tools</text>
  <circle cx="135" cy="258" r="10" stroke-width="1.5"/><text x="135" y="262" text-anchor="middle" font-size="10" font-weight="700" fill="currentColor" stroke="none">4</text>
  <rect x="20" y="270" width="230" height="150" rx="10" stroke-width="1.5"/>
  <line x1="20" y1="292" x2="250" y2="292" stroke-width="1"/>
  <circle cx="32" cy="281" r="2.5" stroke-width="1"/><circle cx="42" cy="281" r="2.5" stroke-width="1"/><circle cx="52" cy="281" r="2.5" stroke-width="1"/>
  <rect x="64" y="276" width="176" height="10" rx="5" stroke-width="1" opacity="0.5"/>
  <text x="34" y="312" font-size="10" font-weight="700" fill="currentColor" stroke="none">Invite your team</text>
  <text x="34" y="325" font-size="7.5" fill="currentColor" stroke="none" opacity="0.6">Add teammates by email — or skip.</text>
  <text x="34" y="342" font-size="7.5" fill="currentColor" stroke="none" opacity="0.7">Email addresses</text>
  <rect x="34" y="346" width="182" height="14" rx="4" stroke-width="1"/><text x="40" y="356" font-size="7.5" fill="currentColor" stroke="none" opacity="0.45">sam@example.com, lee@example.com</text>
  <rect x="34" y="366" width="50" height="13" rx="6.5" stroke-width="1" opacity="0.7"/><text x="59" y="375.5" text-anchor="middle" font-size="8" fill="currentColor" stroke="none" opacity="0.8">Member</text>
  <rect class="text-accent" x="92" y="365" width="78" height="15" rx="5" stroke-width="2.25"/><text class="text-accent" x="131" y="375.5" text-anchor="middle" font-size="8.5" font-weight="700" fill="currentColor" stroke="none">Send invites</text>
  <rect x="176" y="365" width="40" height="15" rx="5" stroke-width="1.25" opacity="0.8"/><text x="196" y="375.5" text-anchor="middle" font-size="8.5" font-weight="600" fill="currentColor" stroke="none" opacity="0.75">Skip</text>
  <rect class="text-accent" x="290" y="270" width="230" height="150" rx="10" stroke-width="2"/>
  <line x1="290" y1="292" x2="520" y2="292" stroke-width="1"/>
  <circle cx="302" cy="281" r="2.5" stroke-width="1"/><circle cx="312" cy="281" r="2.5" stroke-width="1"/><circle cx="322" cy="281" r="2.5" stroke-width="1"/>
  <rect x="334" y="276" width="176" height="10" rx="5" stroke-width="1" opacity="0.5"/>
  <text x="304" y="312" font-size="10" font-weight="700" fill="currentColor" stroke="none">Acme Website</text>
  <rect class="text-accent" x="304" y="320" width="74" height="15" rx="4" stroke-width="2"/><text class="text-accent" x="341" y="330.5" text-anchor="middle" font-size="7.5" font-weight="700" fill="currentColor" stroke="none">Docs &amp; Files</text>
  <rect x="304" y="346" width="182" height="6" rx="3" fill="currentColor" stroke="none" opacity="0.16"/>
  <rect x="304" y="358" width="150" height="6" rx="3" fill="currentColor" stroke="none" opacity="0.16"/>
  <rect x="304" y="370" width="170" height="6" rx="3" fill="currentColor" stroke="none" opacity="0.16"/>
  <path d="M250 125 H288" stroke-width="1.5" marker-end="url(#flowarrow-d2)"/><text x="269" y="119" text-anchor="middle" font-size="9" fill="currentColor" stroke="none" opacity="0.6">next</text>
  <path d="M520 125 H558" stroke-width="1.5" marker-end="url(#flowarrow-d2)"/><text x="539" y="119" text-anchor="middle" font-size="9" fill="currentColor" stroke="none" opacity="0.6">next</text>
  <path d="M675 200 V236 H135 V266" stroke-width="1.5" opacity="0.6" marker-end="url(#flowarrow-d2)"/><text x="405" y="231" text-anchor="middle" font-size="9" fill="currentColor" stroke="none" opacity="0.6">first project saved</text>
  <path d="M250 345 H288" stroke-width="1.5" marker-end="url(#flowarrow-d2)"/><text x="269" y="339" text-anchor="middle" font-size="9" fill="currentColor" stroke="none" opacity="0.6">finish</text>
  <text x="135" y="216" text-anchor="middle" font-size="10" fill="currentColor" stroke="none">Name workspace</text>
  <text x="405" y="216" text-anchor="middle" font-size="10" fill="currentColor" stroke="none">First project</text>
  <text x="675" y="216" text-anchor="middle" font-size="10" fill="currentColor" stroke="none">Pick tools</text>
  <text x="675" y="229" text-anchor="middle" font-size="8" fill="currentColor" stroke="none" opacity="0.55">self-hides unless &gt;1 tool</text>
  <text x="135" y="438" text-anchor="middle" font-size="10" fill="currentColor" stroke="none">Invite team</text>
  <text x="405" y="438" text-anchor="middle" font-size="10" fill="currentColor" stroke="none">Project home</text>
</svg>

## 3 · Project home & tools

Each project enables a set of tools, shown as tabs; the team toggles them in settings. See: [Project tools](/docs/project-tools), [Projects](/docs/projects).

<svg viewBox="0 0 600 305" width="100%" role="img" aria-label="Project home and tools, two screens. Screen one, the project home for Acme Website in the Acme Co workspace, with an active Docs and Files tab and a Project tools settings entry. An arrow labelled open settings leads to screen two, Project tools settings: Choose which tools this project uses, a checked Docs and Files option described as Documents and files for this project, and a Save tools button. Note: the base ships one tool, Docs and Files; forks register more in config slash initializers slash project_tools.rb and the tab bar grows automatically." fill="none" stroke="currentColor" font-family="ui-sans-serif, system-ui, sans-serif">
  <defs><marker id="flowarrow-d3" markerWidth="9" markerHeight="9" refX="6.5" refY="3" orient="auto"><path d="M0,0 L8,3 L0,6 z" fill="currentColor" stroke="none"/></marker></defs>
  <rect x="20" y="40" width="250" height="155" rx="10" stroke-width="1.5"/>
  <line x1="20" y1="62" x2="270" y2="62" stroke-width="1"/>
  <circle cx="32" cy="51" r="2.5" stroke-width="1"/><circle cx="42" cy="51" r="2.5" stroke-width="1"/><circle cx="52" cy="51" r="2.5" stroke-width="1"/>
  <rect x="64" y="46" width="196" height="11" rx="5" stroke-width="1" opacity="0.5"/>
  <text x="36" y="82" font-size="7" fill="currentColor" stroke="none" opacity="0.5">Acme Co</text>
  <text x="36" y="96" font-size="11" font-weight="700" fill="currentColor" stroke="none">Acme Website</text>
  <rect class="text-accent" x="36" y="104" width="80" height="15" rx="4" stroke-width="2"/><text class="text-accent" x="76" y="114.5" text-anchor="middle" font-size="7.5" font-weight="700" fill="currentColor" stroke="none">Docs &amp; Files</text>
  <text x="124" y="115" font-size="8" fill="currentColor" stroke="none" opacity="0.55">Project tools</text>
  <rect x="36" y="132" width="200" height="6" rx="3" fill="currentColor" stroke="none" opacity="0.16"/>
  <rect x="36" y="144" width="160" height="6" rx="3" fill="currentColor" stroke="none" opacity="0.16"/>
  <rect x="36" y="156" width="180" height="6" rx="3" fill="currentColor" stroke="none" opacity="0.16"/>
  <rect x="330" y="40" width="250" height="155" rx="10" stroke-width="1.5"/>
  <line x1="330" y1="62" x2="580" y2="62" stroke-width="1"/>
  <circle cx="342" cy="51" r="2.5" stroke-width="1"/><circle cx="352" cy="51" r="2.5" stroke-width="1"/><circle cx="362" cy="51" r="2.5" stroke-width="1"/>
  <rect x="374" y="46" width="196" height="11" rx="5" stroke-width="1" opacity="0.5"/>
  <text x="346" y="84" font-size="11" font-weight="700" fill="currentColor" stroke="none">Project tools</text>
  <text x="346" y="100" font-size="7.5" fill="currentColor" stroke="none" opacity="0.6">Choose which tools this project uses.</text>
  <text x="346" y="110" font-size="7.5" fill="currentColor" stroke="none" opacity="0.6">You can change this anytime.</text>
  <rect class="text-accent" x="346" y="120" width="11" height="11" rx="3" stroke-width="1.25"/><path class="text-accent" d="M348.5,125.5 L350.5,128 L354.5,123" stroke-width="1.5"/>
  <text x="363" y="129" font-size="8.5" fill="currentColor" stroke="none">Docs &amp; Files</text>
  <text x="363" y="141" font-size="7" fill="currentColor" stroke="none" opacity="0.5">Documents and files for this project.</text>
  <rect class="text-accent" x="346" y="152" width="90" height="16" rx="5" stroke-width="2.25"/><text class="text-accent" x="391" y="163" text-anchor="middle" font-size="8.5" font-weight="700" fill="currentColor" stroke="none">Save tools</text>
  <path d="M270 115 H328" stroke-width="1.5" marker-end="url(#flowarrow-d3)"/><text x="299" y="109" text-anchor="middle" font-size="9" fill="currentColor" stroke="none" opacity="0.6">settings</text>
  <text x="145" y="213" text-anchor="middle" font-size="10" fill="currentColor" stroke="none">Project home</text>
  <text x="455" y="213" text-anchor="middle" font-size="10" fill="currentColor" stroke="none">Settings · Project tools</text>
  <rect x="20" y="232" width="560" height="58" rx="5" stroke-width="1" opacity="0.5"/>
  <text x="30" y="247" font-size="9" font-weight="700" fill="currentColor" stroke="none" opacity="0.7">Note</text>
  <text x="30" y="262" font-size="8.5" fill="currentColor" stroke="none" opacity="0.65">Base ships one tool — Docs &amp; Files. Forks register more in</text>
  <text x="30" y="276" font-size="8.5" fill="currentColor" stroke="none" opacity="0.65">config/initializers/project_tools.rb; the tab bar and this checklist grow automatically.</text>
</svg>

## 4 · Invite teammates

A manager invites people into the workspace with a role; the invitee accepts by email. See: [Workspaces](/docs/workspaces).

<svg viewBox="0 0 600 530" width="100%" role="img" aria-label="Inviting teammates. Admin row: Invite members with an Email addresses field, a hint one email per line or comma-separated, a Member role, and Send invitations; or, as an alternative, Generate a shareable magic link where anyone with the link joins with the chosen role. A dashed arrow labelled invitation sent leads to the invitee row: an invitation email, Jamie has invited you to join Acme Co as a Member, with Accept invitation and Decline invitation and a 7-day expiry; then Set up your login for new users with First name and Create password and a Join button. Notes: roles are Owner, Admin, Member, Viewer, per workspace with JSON permissions; accept branches to one-click for existing users or set-up for new emails, and an EmailMismatch guard blocks a leaked link." fill="none" stroke="currentColor" font-family="ui-sans-serif, system-ui, sans-serif">
  <defs><marker id="flowarrow-d4" markerWidth="9" markerHeight="9" refX="6.5" refY="3" orient="auto"><path d="M0,0 L8,3 L0,6 z" fill="currentColor" stroke="none"/></marker></defs>
  <text x="20" y="42" font-size="10" font-weight="600" fill="currentColor" stroke="none" opacity="0.55">Admin</text>
  <text x="20" y="252" font-size="10" font-weight="600" fill="currentColor" stroke="none" opacity="0.55">Invitee</text>
  <rect x="20" y="50" width="250" height="160" rx="10" stroke-width="1.5"/>
  <line x1="20" y1="72" x2="270" y2="72" stroke-width="1"/>
  <circle cx="32" cy="61" r="2.5" stroke-width="1"/><circle cx="42" cy="61" r="2.5" stroke-width="1"/><circle cx="52" cy="61" r="2.5" stroke-width="1"/>
  <rect x="64" y="56" width="196" height="10" rx="5" stroke-width="1" opacity="0.5"/>
  <text x="36" y="92" font-size="11" font-weight="700" fill="currentColor" stroke="none">Invite members</text>
  <text x="36" y="110" font-size="7.5" fill="currentColor" stroke="none" opacity="0.7">Email addresses</text>
  <rect x="36" y="114" width="200" height="15" rx="4" stroke-width="1"/><text x="42" y="124" font-size="7.5" fill="currentColor" stroke="none" opacity="0.45">sam@acme.com, lee@acme.com</text>
  <text x="36" y="139" font-size="7" fill="currentColor" stroke="none" opacity="0.5">One email per line, or comma-separated.</text>
  <text x="36" y="153" font-size="7.5" fill="currentColor" stroke="none" opacity="0.7">Role</text>
  <rect x="66" y="145" width="70" height="13" rx="3" stroke-width="1" opacity="0.7"/><text x="101" y="154.5" text-anchor="middle" font-size="8" fill="currentColor" stroke="none" opacity="0.8">Member ▾</text>
  <rect class="text-accent" x="36" y="166" width="120" height="16" rx="5" stroke-width="2.25"/><text class="text-accent" x="96" y="177" text-anchor="middle" font-size="8.5" font-weight="700" fill="currentColor" stroke="none">Send invitations</text>
  <rect x="330" y="50" width="250" height="160" rx="10" stroke-width="1.5"/>
  <line x1="330" y1="72" x2="580" y2="72" stroke-width="1"/>
  <circle cx="342" cy="61" r="2.5" stroke-width="1"/><circle cx="352" cy="61" r="2.5" stroke-width="1"/><circle cx="362" cy="61" r="2.5" stroke-width="1"/>
  <rect x="374" y="56" width="196" height="10" rx="5" stroke-width="1" opacity="0.5"/>
  <text x="346" y="92" font-size="9.5" font-weight="700" fill="currentColor" stroke="none">Generate a shareable magic link</text>
  <text x="346" y="108" font-size="7.5" fill="currentColor" stroke="none" opacity="0.6">Anyone with the link can join with the</text>
  <text x="346" y="118" font-size="7.5" fill="currentColor" stroke="none" opacity="0.6">role you select.</text>
  <text x="346" y="134" font-size="7.5" fill="currentColor" stroke="none" opacity="0.7">Role</text>
  <rect x="376" y="126" width="70" height="13" rx="3" stroke-width="1" opacity="0.7"/><text x="411" y="135.5" text-anchor="middle" font-size="8" fill="currentColor" stroke="none" opacity="0.8">Member ▾</text>
  <rect class="text-accent" x="346" y="150" width="110" height="16" rx="5" stroke-width="2.25"/><text class="text-accent" x="401" y="161" text-anchor="middle" font-size="8.5" font-weight="700" fill="currentColor" stroke="none">Generate link</text>
  <text x="300" y="130" text-anchor="middle" font-size="9" fill="currentColor" stroke="none" opacity="0.55">or</text>
  <rect x="20" y="260" width="250" height="150" rx="10" stroke-width="1.5"/>
  <line x1="20" y1="282" x2="270" y2="282" stroke-width="1"/>
  <circle cx="32" cy="271" r="2.5" stroke-width="1"/><circle cx="42" cy="271" r="2.5" stroke-width="1"/><circle cx="52" cy="271" r="2.5" stroke-width="1"/>
  <rect x="64" y="266" width="196" height="10" rx="5" stroke-width="1" opacity="0.5"/>
  <text x="36" y="302" font-size="9.5" font-weight="700" fill="currentColor" stroke="none">You've been invited to Acme Co</text>
  <text x="36" y="320" font-size="8" fill="currentColor" stroke="none" opacity="0.65">Jamie has invited you to join Acme Co</text>
  <text x="36" y="330" font-size="8" fill="currentColor" stroke="none" opacity="0.65">as a Member.</text>
  <rect class="text-accent" x="36" y="342" width="118" height="17" rx="5" stroke-width="2.25"/><text class="text-accent" x="95" y="354" text-anchor="middle" font-size="8.5" font-weight="700" fill="currentColor" stroke="none">Accept invitation</text>
  <rect x="160" y="342" width="100" height="17" rx="5" stroke-width="1.25" opacity="0.8"/><text x="210" y="354" text-anchor="middle" font-size="8" font-weight="600" fill="currentColor" stroke="none" opacity="0.75">Decline</text>
  <text x="36" y="374" font-size="7" fill="currentColor" stroke="none" opacity="0.5">This invitation expires in 7 days.</text>
  <rect x="330" y="260" width="250" height="150" rx="10" stroke-width="1.5"/>
  <line x1="330" y1="282" x2="580" y2="282" stroke-width="1"/>
  <circle cx="342" cy="271" r="2.5" stroke-width="1"/><circle cx="352" cy="271" r="2.5" stroke-width="1"/><circle cx="362" cy="271" r="2.5" stroke-width="1"/>
  <rect x="374" y="266" width="196" height="10" rx="5" stroke-width="1" opacity="0.5"/>
  <text x="346" y="300" font-size="11" font-weight="700" fill="currentColor" stroke="none">Set up your login</text>
  <text x="346" y="312" font-size="7" fill="currentColor" stroke="none" opacity="0.55">New users — existing users join in one click.</text>
  <text x="346" y="328" font-size="7.5" fill="currentColor" stroke="none" opacity="0.7">First name</text>
  <rect x="346" y="332" width="200" height="14" rx="4" stroke-width="1"/><text x="352" y="342" font-size="8.5" fill="currentColor" stroke="none" opacity="0.45">Sam Diaz</text>
  <text x="346" y="358" font-size="7.5" fill="currentColor" stroke="none" opacity="0.7">Create password</text>
  <rect x="346" y="362" width="200" height="14" rx="4" stroke-width="1"/><text x="352" y="372" font-size="8.5" fill="currentColor" stroke="none" opacity="0.45">••••••••••••</text>
  <rect class="text-accent" x="346" y="384" width="110" height="16" rx="5" stroke-width="2.25"/><text class="text-accent" x="401" y="395" text-anchor="middle" font-size="8.5" font-weight="700" fill="currentColor" stroke="none">Join Acme Co</text>
  <path d="M135 210 V258" stroke-width="1.5" stroke-dasharray="6 4" opacity="0.6" marker-end="url(#flowarrow-d4)"/><text x="200" y="240" text-anchor="middle" font-size="9" fill="currentColor" stroke="none" opacity="0.6">invitation sent</text>
  <path d="M270 335 H328" stroke-width="1.5" marker-end="url(#flowarrow-d4)"/><text x="299" y="329" text-anchor="middle" font-size="9" fill="currentColor" stroke="none" opacity="0.6">Accept</text>
  <text x="145" y="228" text-anchor="middle" font-size="10" fill="currentColor" stroke="none">Invite members</text>
  <text x="455" y="228" text-anchor="middle" font-size="10" fill="currentColor" stroke="none">Alternative: shareable link</text>
  <text x="145" y="428" text-anchor="middle" font-size="10" fill="currentColor" stroke="none">Invitation email</text>
  <text x="455" y="428" text-anchor="middle" font-size="10" fill="currentColor" stroke="none">Accept → in the workspace</text>
  <rect x="20" y="442" width="560" height="30" rx="5" stroke-width="1" opacity="0.5"/>
  <text x="30" y="461" font-size="8.5" fill="currentColor" stroke="none" opacity="0.65">Roles: Owner · Admin · Member · Viewer — per workspace, JSON permissions. Set at invite time.</text>
  <rect x="20" y="478" width="560" height="46" rx="5" stroke-width="1" opacity="0.5"/>
  <text x="30" y="493" font-size="8.5" fill="currentColor" stroke="none" opacity="0.65">Accept branches: existing user → one-click join · new email → set up a login.</text>
  <text x="30" y="506" font-size="8.5" fill="currentColor" stroke="none" opacity="0.65">EmailMismatch guard blocks a leaked link claimed by another address.</text>
</svg>

## 5 · Clientside

A project can open a separate, read-only area for an external client, who never becomes a member. See: [Clientside](/docs/clientside).

<svg viewBox="0 0 820 510" width="100%" role="img" aria-label="Clientside. Team row: Client access, a separate limited view for external clients, with a toggle Turn on Clientside for this project and Save. Edit document, with a checked Share with the client side checkbox shown only when Clientside is on. Invite a client, with Client email (dana at bigco.com) and Their company (BigCo) fields and Send client invite. A dashed arrow labelled invite email sent drops to the Client row: the client email, Jamie shared the project Acme Website with you, View the invitation; then the accent-highlighted client area, Acme Co Client area, Shared with you, listing read-only items. Note: a client is a ClientAccess not a member with no seat; the area never sets Current.workspace and shows only resources that are shared and published; an EmailMismatch guard protects the invite link." fill="none" stroke="currentColor" font-family="ui-sans-serif, system-ui, sans-serif">
  <defs><marker id="flowarrow-d5" markerWidth="9" markerHeight="9" refX="6.5" refY="3" orient="auto"><path d="M0,0 L8,3 L0,6 z" fill="currentColor" stroke="none"/></marker></defs>
  <text x="20" y="42" font-size="10" font-weight="600" fill="currentColor" stroke="none" opacity="0.55">Team</text>
  <text x="20" y="262" font-size="10" font-weight="600" fill="currentColor" stroke="none" opacity="0.55">Client</text>
  <rect x="20" y="50" width="230" height="150" rx="10" stroke-width="1.5"/>
  <line x1="20" y1="72" x2="250" y2="72" stroke-width="1"/>
  <circle cx="32" cy="61" r="2.5" stroke-width="1"/><circle cx="42" cy="61" r="2.5" stroke-width="1"/><circle cx="52" cy="61" r="2.5" stroke-width="1"/>
  <rect x="64" y="56" width="176" height="10" rx="5" stroke-width="1" opacity="0.5"/>
  <text x="34" y="92" font-size="11" font-weight="700" fill="currentColor" stroke="none">Client access</text>
  <text x="34" y="104" font-size="7" fill="currentColor" stroke="none" opacity="0.6">A separate, limited view for external</text>
  <text x="34" y="113" font-size="7" fill="currentColor" stroke="none" opacity="0.6">clients of this project.</text>
  <rect class="text-accent" x="34" y="122" width="26" height="13" rx="6.5" stroke-width="1.25"/><circle class="text-accent" cx="55" cy="128.5" r="4.5" fill="currentColor" stroke="none"/>
  <text x="66" y="131" font-size="7.5" fill="currentColor" stroke="none">Turn on Clientside for this project</text>
  <rect class="text-accent" x="34" y="150" width="70" height="16" rx="5" stroke-width="2.25"/><text class="text-accent" x="69" y="161" text-anchor="middle" font-size="9" font-weight="700" fill="currentColor" stroke="none">Save</text>
  <rect x="290" y="50" width="230" height="150" rx="10" stroke-width="1.5"/>
  <line x1="290" y1="72" x2="520" y2="72" stroke-width="1"/>
  <circle cx="302" cy="61" r="2.5" stroke-width="1"/><circle cx="312" cy="61" r="2.5" stroke-width="1"/><circle cx="322" cy="61" r="2.5" stroke-width="1"/>
  <rect x="334" y="56" width="176" height="10" rx="5" stroke-width="1" opacity="0.5"/>
  <text x="304" y="92" font-size="11" font-weight="700" fill="currentColor" stroke="none">Edit document</text>
  <text x="304" y="108" font-size="7.5" fill="currentColor" stroke="none" opacity="0.7">Title</text>
  <rect x="304" y="112" width="196" height="14" rx="4" stroke-width="1"/><text x="310" y="122" font-size="8.5" fill="currentColor" stroke="none" opacity="0.45">Kickoff brief</text>
  <rect class="text-accent" x="304" y="134" width="11" height="11" rx="3" stroke-width="1.25"/><path class="text-accent" d="M306.5,139.5 L308.5,142 L312.5,137" stroke-width="1.5"/>
  <text x="321" y="143" font-size="8.5" fill="currentColor" stroke="none">Share with the client side</text>
  <text x="321" y="155" font-size="7" fill="currentColor" stroke="none" opacity="0.5">shown only when Clientside is on</text>
  <rect class="text-accent" x="304" y="164" width="70" height="16" rx="5" stroke-width="2.25"/><text class="text-accent" x="339" y="175" text-anchor="middle" font-size="9" font-weight="700" fill="currentColor" stroke="none">Save</text>
  <rect x="560" y="50" width="230" height="150" rx="10" stroke-width="1.5"/>
  <line x1="560" y1="72" x2="790" y2="72" stroke-width="1"/>
  <circle cx="572" cy="61" r="2.5" stroke-width="1"/><circle cx="582" cy="61" r="2.5" stroke-width="1"/><circle cx="592" cy="61" r="2.5" stroke-width="1"/>
  <rect x="604" y="56" width="176" height="10" rx="5" stroke-width="1" opacity="0.5"/>
  <text x="574" y="92" font-size="11" font-weight="700" fill="currentColor" stroke="none">Invite a client</text>
  <text x="574" y="104" font-size="7" fill="currentColor" stroke="none" opacity="0.6">They'll get a separate, limited view.</text>
  <text x="574" y="120" font-size="7.5" fill="currentColor" stroke="none" opacity="0.7">Client email</text>
  <rect x="574" y="124" width="196" height="14" rx="4" stroke-width="1"/><text x="580" y="134" font-size="8.5" fill="currentColor" stroke="none" opacity="0.45">dana@bigco.com</text>
  <text x="574" y="150" font-size="7.5" fill="currentColor" stroke="none" opacity="0.7">Their company</text>
  <rect x="574" y="154" width="196" height="14" rx="4" stroke-width="1"/><text x="580" y="164" font-size="8.5" fill="currentColor" stroke="none" opacity="0.45">BigCo</text>
  <rect class="text-accent" x="574" y="176" width="124" height="16" rx="5" stroke-width="2.25"/><text class="text-accent" x="636" y="187" text-anchor="middle" font-size="8.5" font-weight="700" fill="currentColor" stroke="none">Send client invite</text>
  <rect x="20" y="270" width="230" height="150" rx="10" stroke-width="1.5"/>
  <line x1="20" y1="292" x2="250" y2="292" stroke-width="1"/>
  <circle cx="32" cy="281" r="2.5" stroke-width="1"/><circle cx="42" cy="281" r="2.5" stroke-width="1"/><circle cx="52" cy="281" r="2.5" stroke-width="1"/>
  <rect x="64" y="276" width="176" height="10" rx="5" stroke-width="1" opacity="0.5"/>
  <text x="34" y="312" font-size="9.5" font-weight="700" fill="currentColor" stroke="none">You've been invited to</text>
  <text x="34" y="324" font-size="9.5" font-weight="700" fill="currentColor" stroke="none">Acme Website</text>
  <text x="34" y="342" font-size="8" fill="currentColor" stroke="none" opacity="0.65">Jamie shared the project Acme</text>
  <text x="34" y="352" font-size="8" fill="currentColor" stroke="none" opacity="0.65">Website with you.</text>
  <rect class="text-accent" x="34" y="364" width="130" height="17" rx="5" stroke-width="2.25"/><text class="text-accent" x="99" y="375.5" text-anchor="middle" font-size="8.5" font-weight="700" fill="currentColor" stroke="none">View the invitation</text>
  <rect class="text-accent" x="290" y="270" width="230" height="150" rx="10" stroke-width="2"/>
  <line x1="290" y1="292" x2="520" y2="292" stroke-width="1"/>
  <circle cx="302" cy="281" r="2.5" stroke-width="1"/><circle cx="312" cy="281" r="2.5" stroke-width="1"/><circle cx="322" cy="281" r="2.5" stroke-width="1"/>
  <rect x="334" y="276" width="176" height="10" rx="5" stroke-width="1" opacity="0.5"/>
  <text x="304" y="312" font-size="10" font-weight="700" fill="currentColor" stroke="none">Acme Co · Client area</text>
  <text x="304" y="326" font-size="8" fill="currentColor" stroke="none" opacity="0.7">Shared with you</text>
  <rect x="304" y="338" width="186" height="7" rx="3" fill="currentColor" stroke="none" opacity="0.16"/>
  <rect x="304" y="352" width="160" height="7" rx="3" fill="currentColor" stroke="none" opacity="0.16"/>
  <rect x="304" y="366" width="176" height="7" rx="3" fill="currentColor" stroke="none" opacity="0.16"/>
  <path d="M250 125 H288" stroke-width="1.5" marker-end="url(#flowarrow-d5)"/><text x="269" y="119" text-anchor="middle" font-size="9" fill="currentColor" stroke="none" opacity="0.6">share</text>
  <path d="M520 125 H558" stroke-width="1.5" marker-end="url(#flowarrow-d5)"/><text x="539" y="119" text-anchor="middle" font-size="9" fill="currentColor" stroke="none" opacity="0.6">invite</text>
  <path d="M675 200 V236 H135 V266" stroke-width="1.5" stroke-dasharray="6 4" opacity="0.6" marker-end="url(#flowarrow-d5)"/><text x="405" y="231" text-anchor="middle" font-size="9" fill="currentColor" stroke="none" opacity="0.6">invite email sent</text>
  <path d="M250 345 H288" stroke-width="1.5" marker-end="url(#flowarrow-d5)"/><text x="269" y="339" text-anchor="middle" font-size="9" fill="currentColor" stroke="none" opacity="0.6">View</text>
  <text x="135" y="216" text-anchor="middle" font-size="10" fill="currentColor" stroke="none">Enable Clientside</text>
  <text x="405" y="216" text-anchor="middle" font-size="10" fill="currentColor" stroke="none">Share a resource</text>
  <text x="675" y="216" text-anchor="middle" font-size="10" fill="currentColor" stroke="none">Invite a client</text>
  <text x="135" y="438" text-anchor="middle" font-size="10" fill="currentColor" stroke="none">Client email</text>
  <text x="405" y="438" text-anchor="middle" font-size="10" fill="currentColor" stroke="none">Client area (read-only)</text>
  <rect x="20" y="452" width="780" height="46" rx="5" stroke-width="1" opacity="0.5"/>
  <text x="30" y="471" font-size="8.5" fill="currentColor" stroke="none" opacity="0.65">A client is a ClientAccess, not a member — no seat. The client area never sets Current.workspace.</text>
  <text x="30" y="486" font-size="8.5" fill="currentColor" stroke="none" opacity="0.65">It shows only resources that are shared AND published. The EmailMismatch guard protects the invite link.</text>
</svg>
