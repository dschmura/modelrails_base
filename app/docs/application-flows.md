---
title: Application Flows
description: A visual map of every current user journey — sign up & verify, first-run onboarding, project home & tools, inviting teammates, and Clientside — as low-fi wireframes.
keywords: wireframes flows journeys onboarding signup verify project tools invite teammates members clientside client diagram
audience: [guide, technical]
---

# Application Flows

Low-fi wireframes of the app's five core journeys, as they work today. Each row is a sequence of screens; arrows are transitions. These illustrate flow and information architecture, not final visual design. For the behavior behind each one, follow the "See:" link under its heading.

The wireframes adapt to light and dark themes and are described for screen readers.

## Legend

- **Bold outline** = primary action · **thin outline** = secondary action.
- **Accent** elements (toggles, active tabs, the final screen) mark the emphasized or "after" state.
- **Dashed** box = placeholder/empty content · **dashed arrow** = an email/async hop.
- **Numbered badge** = an ordered wizard step · faint sub-line = an edge case or note.

## 1 · Sign up & verify

A new member creates an account and is asked to confirm their email — a soft, non-blocking gate. See: [Email & verification](/docs/emails), [Accounts](/docs/accounts).

<svg viewBox="0 0 760 230" width="100%" role="img" aria-label="Sign up and verify, three screens left to right. Screen one, a welcome landing page with a primary Create account button and a secondary Sign in button. An arrow labelled Create account leads to screen two, the create-account form with Name, Work email, and Password fields, a primary Create account button, and email or OAuth sign-up. An arrow labelled submit leads to screen three, a Check your email screen with a placeholder envelope, the message that a link was sent, and a secondary Resend button; verification is non-blocking and a reminder banner also appears." fill="none" stroke="currentColor" font-family="ui-sans-serif, system-ui, sans-serif">
  <defs><marker id="flowarrow-1" markerWidth="9" markerHeight="9" refX="6.5" refY="3" orient="auto"><path d="M0,0 L8,3 L0,6 z" fill="currentColor" stroke="none"/></marker></defs>

  <!-- Screen 1: Welcome (x=16) -->
  <rect x="16" y="40" width="200" height="140" rx="12" stroke-width="1.5"/>
  <line x1="16" y1="64" x2="216" y2="64" stroke-width="1"/>
  <circle cx="30" cy="52" r="3" stroke-width="1"/><circle cx="42" cy="52" r="3" stroke-width="1"/><circle cx="54" cy="52" r="3" stroke-width="1"/>
  <rect x="70" y="46" width="132" height="12" rx="6" stroke-width="1" opacity="0.5"/>
  <rect x="36" y="84" width="110" height="8" rx="4" fill="currentColor" stroke="none" opacity="0.4"/>
  <rect x="36" y="104" width="150" height="6" rx="3" fill="currentColor" stroke="none" opacity="0.16"/>
  <rect x="36" y="116" width="120" height="6" rx="3" fill="currentColor" stroke="none" opacity="0.16"/>
  <rect class="text-accent" x="36" y="140" width="92" height="18" rx="5" stroke-width="2.25"/>
  <text class="text-accent" x="82" y="152.5" text-anchor="middle" font-size="9" font-weight="700" fill="currentColor" stroke="none">Create account</text>
  <rect x="136" y="140" width="60" height="18" rx="5" stroke-width="1.25" opacity="0.8"/>
  <text x="166" y="152.5" text-anchor="middle" font-size="9" font-weight="600" fill="currentColor" stroke="none" opacity="0.75">Sign in</text>

  <!-- Screen 2: Create account (x=280) -->
  <rect x="280" y="40" width="200" height="140" rx="12" stroke-width="1.5"/>
  <line x1="280" y1="64" x2="480" y2="64" stroke-width="1"/>
  <circle cx="294" cy="52" r="3" stroke-width="1"/><circle cx="306" cy="52" r="3" stroke-width="1"/><circle cx="318" cy="52" r="3" stroke-width="1"/>
  <rect x="334" y="46" width="132" height="12" rx="6" stroke-width="1" opacity="0.5"/>
  <rect x="300" y="78" width="120" height="8" rx="4" fill="currentColor" stroke="none" opacity="0.4"/>
  <rect x="300" y="92" width="160" height="14" rx="4" stroke-width="1"/><rect x="306" y="97" width="64" height="4" rx="2" fill="currentColor" stroke="none" opacity="0.3"/>
  <rect x="300" y="110" width="160" height="14" rx="4" stroke-width="1"/><rect x="306" y="115" width="64" height="4" rx="2" fill="currentColor" stroke="none" opacity="0.3"/>
  <rect x="300" y="128" width="160" height="14" rx="4" stroke-width="1"/><rect x="306" y="133" width="64" height="4" rx="2" fill="currentColor" stroke="none" opacity="0.3"/>
  <rect class="text-accent" x="300" y="148" width="160" height="18" rx="5" stroke-width="2.25"/>
  <text class="text-accent" x="380" y="160.5" text-anchor="middle" font-size="9" font-weight="700" fill="currentColor" stroke="none">Create account</text>

  <!-- Screen 3: Check your email (x=544) -->
  <rect x="544" y="40" width="200" height="140" rx="12" stroke-width="1.5"/>
  <line x1="544" y1="64" x2="744" y2="64" stroke-width="1"/>
  <circle cx="558" cy="52" r="3" stroke-width="1"/><circle cx="570" cy="52" r="3" stroke-width="1"/><circle cx="582" cy="52" r="3" stroke-width="1"/>
  <rect x="598" y="46" width="132" height="12" rx="6" stroke-width="1" opacity="0.5"/>
  <rect x="564" y="78" width="130" height="8" rx="4" fill="currentColor" stroke="none" opacity="0.4"/>
  <rect x="614" y="92" width="60" height="34" rx="6" stroke-width="1.25" stroke-dasharray="5 4" opacity="0.6"/>
  <text x="644" y="113" text-anchor="middle" font-size="14" fill="currentColor" stroke="none" opacity="0.45">✉</text>
  <rect x="564" y="134" width="160" height="6" rx="3" fill="currentColor" stroke="none" opacity="0.16"/>
  <rect x="564" y="150" width="70" height="18" rx="5" stroke-width="1.25" opacity="0.8"/>
  <text x="599" y="162.5" text-anchor="middle" font-size="9" font-weight="600" fill="currentColor" stroke="none" opacity="0.75">Resend</text>

  <!-- Connectors -->
  <path d="M216 110 H278" stroke-width="1.5" marker-end="url(#flowarrow-1)"/>
  <text x="248" y="104" text-anchor="middle" font-size="9.5" fill="currentColor" stroke="none" opacity="0.6">Create account</text>
  <path d="M480 110 H542" stroke-width="1.5" marker-end="url(#flowarrow-1)"/>
  <text x="512" y="104" text-anchor="middle" font-size="9.5" fill="currentColor" stroke="none" opacity="0.6">submit</text>

  <!-- Captions -->
  <text x="116" y="198" text-anchor="middle" font-size="11" fill="currentColor" stroke="none">Welcome</text>
  <text x="380" y="198" text-anchor="middle" font-size="11" fill="currentColor" stroke="none">Create account (+ OAuth)</text>
  <text x="644" y="198" text-anchor="middle" font-size="11" fill="currentColor" stroke="none">Check your email</text>
  <text x="644" y="211" text-anchor="middle" font-size="9.5" fill="currentColor" stroke="none" opacity="0.55">non-blocking · reminder banner</text>
</svg>

## 2 · First-run onboarding

Under the `none` posture, a new user's first session is a short, resumable wizard before they reach the app. See: [Onboarding](/docs/onboarding).

<svg viewBox="0 0 760 480" width="100%" role="img" aria-label="First-run onboarding wizard, six numbered screens over two rows. Step one, check your email with a Resend button. Step two, name your workspace, one field and Continue. Step three, create your first project, one field and Continue. A connector labelled first project saved drops to the second row. Step four, choose tools, a checklist with Docs enabled and a Continue button; this step self-hides unless more than one tool is registered. Step five, invite teammates, an emails field with a Member role and Send invites or Skip. The final screen, the project home, an accent-highlighted window with an active Docs tab." fill="none" stroke="currentColor" font-family="ui-sans-serif, system-ui, sans-serif">
  <defs><marker id="flowarrow-2" markerWidth="9" markerHeight="9" refX="6.5" refY="3" orient="auto"><path d="M0,0 L8,3 L0,6 z" fill="currentColor" stroke="none"/></marker></defs>

  <!-- Step 1: Check email (col0, row0) -->
  <circle cx="116" cy="26" r="11" stroke-width="1.5"/><text x="116" y="30" text-anchor="middle" font-size="11" font-weight="700" fill="currentColor" stroke="none">1</text>
  <rect x="16" y="40" width="200" height="140" rx="12" stroke-width="1.5"/>
  <line x1="16" y1="64" x2="216" y2="64" stroke-width="1"/>
  <circle cx="30" cy="52" r="3" stroke-width="1"/><circle cx="42" cy="52" r="3" stroke-width="1"/><circle cx="54" cy="52" r="3" stroke-width="1"/>
  <rect x="70" y="46" width="132" height="12" rx="6" stroke-width="1" opacity="0.5"/>
  <rect x="36" y="80" width="120" height="8" rx="4" fill="currentColor" stroke="none" opacity="0.4"/>
  <rect x="36" y="100" width="150" height="6" rx="3" fill="currentColor" stroke="none" opacity="0.16"/>
  <rect x="36" y="112" width="110" height="6" rx="3" fill="currentColor" stroke="none" opacity="0.16"/>
  <rect x="36" y="142" width="70" height="18" rx="5" stroke-width="1.25" opacity="0.8"/>
  <text x="71" y="154.5" text-anchor="middle" font-size="9" font-weight="600" fill="currentColor" stroke="none" opacity="0.75">Resend</text>

  <!-- Step 2: Name workspace (col1, row0) -->
  <circle cx="380" cy="26" r="11" stroke-width="1.5"/><text x="380" y="30" text-anchor="middle" font-size="11" font-weight="700" fill="currentColor" stroke="none">2</text>
  <rect x="280" y="40" width="200" height="140" rx="12" stroke-width="1.5"/>
  <line x1="280" y1="64" x2="480" y2="64" stroke-width="1"/>
  <circle cx="294" cy="52" r="3" stroke-width="1"/><circle cx="306" cy="52" r="3" stroke-width="1"/><circle cx="318" cy="52" r="3" stroke-width="1"/>
  <rect x="334" y="46" width="132" height="12" rx="6" stroke-width="1" opacity="0.5"/>
  <rect x="300" y="82" width="130" height="8" rx="4" fill="currentColor" stroke="none" opacity="0.4"/>
  <rect x="300" y="100" width="160" height="14" rx="4" stroke-width="1"/><rect x="306" y="105" width="64" height="4" rx="2" fill="currentColor" stroke="none" opacity="0.3"/>
  <rect class="text-accent" x="300" y="140" width="100" height="18" rx="5" stroke-width="2.25"/>
  <text class="text-accent" x="350" y="152.5" text-anchor="middle" font-size="9" font-weight="700" fill="currentColor" stroke="none">Continue</text>

  <!-- Step 3: First project (col2, row0) -->
  <circle cx="644" cy="26" r="11" stroke-width="1.5"/><text x="644" y="30" text-anchor="middle" font-size="11" font-weight="700" fill="currentColor" stroke="none">3</text>
  <rect x="544" y="40" width="200" height="140" rx="12" stroke-width="1.5"/>
  <line x1="544" y1="64" x2="744" y2="64" stroke-width="1"/>
  <circle cx="558" cy="52" r="3" stroke-width="1"/><circle cx="570" cy="52" r="3" stroke-width="1"/><circle cx="582" cy="52" r="3" stroke-width="1"/>
  <rect x="598" y="46" width="132" height="12" rx="6" stroke-width="1" opacity="0.5"/>
  <rect x="564" y="82" width="140" height="8" rx="4" fill="currentColor" stroke="none" opacity="0.4"/>
  <rect x="564" y="100" width="160" height="14" rx="4" stroke-width="1"/><rect x="570" y="105" width="64" height="4" rx="2" fill="currentColor" stroke="none" opacity="0.3"/>
  <rect class="text-accent" x="564" y="140" width="100" height="18" rx="5" stroke-width="2.25"/>
  <text class="text-accent" x="614" y="152.5" text-anchor="middle" font-size="9" font-weight="700" fill="currentColor" stroke="none">Continue</text>

  <!-- Step 4: Choose tools (col0, row1) -->
  <circle cx="116" cy="246" r="11" stroke-width="1.5"/><text x="116" y="250" text-anchor="middle" font-size="11" font-weight="700" fill="currentColor" stroke="none">4</text>
  <rect x="16" y="260" width="200" height="140" rx="12" stroke-width="1.5"/>
  <line x1="16" y1="284" x2="216" y2="284" stroke-width="1"/>
  <circle cx="30" cy="272" r="3" stroke-width="1"/><circle cx="42" cy="272" r="3" stroke-width="1"/><circle cx="54" cy="272" r="3" stroke-width="1"/>
  <rect x="70" y="266" width="132" height="12" rx="6" stroke-width="1" opacity="0.5"/>
  <rect x="36" y="298" width="90" height="8" rx="4" fill="currentColor" stroke="none" opacity="0.4"/>
  <rect class="text-accent" x="36" y="314" width="11" height="11" rx="3" stroke-width="1.25"/>
  <path class="text-accent" d="M38.5,319.5 L40.5,322 L44.5,317" stroke-width="1.5"/>
  <rect x="53" y="317" width="110" height="5" rx="2.5" fill="currentColor" stroke="none" opacity="0.3"/>
  <rect x="36" y="332" width="11" height="11" rx="3" stroke-width="1.25" opacity="0.7"/>
  <rect x="53" y="335" width="90" height="5" rx="2.5" fill="currentColor" stroke="none" opacity="0.22"/>
  <rect class="text-accent" x="36" y="360" width="100" height="18" rx="5" stroke-width="2.25"/>
  <text class="text-accent" x="86" y="372.5" text-anchor="middle" font-size="9" font-weight="700" fill="currentColor" stroke="none">Continue</text>

  <!-- Step 5: Invite teammates (col1, row1) -->
  <circle cx="380" cy="246" r="11" stroke-width="1.5"/><text x="380" y="250" text-anchor="middle" font-size="11" font-weight="700" fill="currentColor" stroke="none">5</text>
  <rect x="280" y="260" width="200" height="140" rx="12" stroke-width="1.5"/>
  <line x1="280" y1="284" x2="480" y2="284" stroke-width="1"/>
  <circle cx="294" cy="272" r="3" stroke-width="1"/><circle cx="306" cy="272" r="3" stroke-width="1"/><circle cx="318" cy="272" r="3" stroke-width="1"/>
  <rect x="334" y="266" width="132" height="12" rx="6" stroke-width="1" opacity="0.5"/>
  <rect x="300" y="298" width="120" height="8" rx="4" fill="currentColor" stroke="none" opacity="0.4"/>
  <rect x="300" y="314" width="160" height="14" rx="4" stroke-width="1"/><rect x="306" y="319" width="90" height="4" rx="2" fill="currentColor" stroke="none" opacity="0.3"/>
  <rect x="300" y="334" width="54" height="14" rx="7" stroke-width="1" opacity="0.7"/>
  <text x="327" y="344" text-anchor="middle" font-size="8.5" fill="currentColor" stroke="none" opacity="0.8">Member</text>
  <rect class="text-accent" x="300" y="360" width="100" height="18" rx="5" stroke-width="2.25"/>
  <text class="text-accent" x="350" y="372.5" text-anchor="middle" font-size="9" font-weight="700" fill="currentColor" stroke="none">Send invites</text>
  <rect x="406" y="360" width="54" height="18" rx="5" stroke-width="1.25" opacity="0.8"/>
  <text x="433" y="372.5" text-anchor="middle" font-size="9" font-weight="600" fill="currentColor" stroke="none" opacity="0.75">Skip</text>

  <!-- Final: Project home (col2, row1) — accent frame -->
  <rect class="text-accent" x="544" y="260" width="200" height="140" rx="12" stroke-width="2"/>
  <line x1="544" y1="284" x2="744" y2="284" stroke-width="1"/>
  <circle cx="558" cy="272" r="3" stroke-width="1"/><circle cx="570" cy="272" r="3" stroke-width="1"/><circle cx="582" cy="272" r="3" stroke-width="1"/>
  <rect x="598" y="266" width="132" height="12" rx="6" stroke-width="1" opacity="0.5"/>
  <rect class="text-accent" x="564" y="298" width="40" height="15" rx="4" stroke-width="2"/>
  <text class="text-accent" x="584" y="308.5" text-anchor="middle" font-size="8" font-weight="700" fill="currentColor" stroke="none">Docs</text>
  <rect x="608" y="298" width="40" height="15" rx="4" stroke-width="1" opacity="0.55"/>
  <rect x="652" y="298" width="40" height="15" rx="4" stroke-width="1" opacity="0.55"/>
  <rect x="564" y="324" width="140" height="8" rx="4" fill="currentColor" stroke="none" opacity="0.4"/>
  <rect x="564" y="342" width="160" height="6" rx="3" fill="currentColor" stroke="none" opacity="0.16"/>
  <rect x="564" y="354" width="130" height="6" rx="3" fill="currentColor" stroke="none" opacity="0.16"/>

  <!-- Connectors -->
  <path d="M216 110 H278" stroke-width="1.5" marker-end="url(#flowarrow-2)"/>
  <text x="247" y="104" text-anchor="middle" font-size="9.5" fill="currentColor" stroke="none" opacity="0.6">Continue</text>
  <path d="M480 110 H542" stroke-width="1.5" marker-end="url(#flowarrow-2)"/>
  <text x="511" y="104" text-anchor="middle" font-size="9.5" fill="currentColor" stroke="none" opacity="0.6">Continue</text>
  <path d="M644 180 V222 H116 V258" stroke-width="1.5" opacity="0.6" marker-end="url(#flowarrow-2)"/>
  <text x="380" y="216" text-anchor="middle" font-size="9.5" fill="currentColor" stroke="none" opacity="0.6">first project saved</text>
  <path d="M216 330 H278" stroke-width="1.5" marker-end="url(#flowarrow-2)"/>
  <text x="247" y="324" text-anchor="middle" font-size="9.5" fill="currentColor" stroke="none" opacity="0.6">Continue</text>
  <path d="M480 330 H542" stroke-width="1.5" marker-end="url(#flowarrow-2)"/>
  <text x="511" y="324" text-anchor="middle" font-size="9.5" fill="currentColor" stroke="none" opacity="0.6">Finish / Skip</text>

  <!-- Captions -->
  <text x="116" y="198" text-anchor="middle" font-size="11" fill="currentColor" stroke="none">Check your email</text>
  <text x="380" y="198" text-anchor="middle" font-size="11" fill="currentColor" stroke="none">Name your workspace</text>
  <text x="644" y="198" text-anchor="middle" font-size="11" fill="currentColor" stroke="none">Create your first project</text>
  <text x="116" y="418" text-anchor="middle" font-size="11" fill="currentColor" stroke="none">Choose tools</text>
  <text x="116" y="431" text-anchor="middle" font-size="9.5" fill="currentColor" stroke="none" opacity="0.55">self-hides unless &gt;1 tool</text>
  <text x="380" y="418" text-anchor="middle" font-size="11" fill="currentColor" stroke="none">Invite teammates (or skip)</text>
  <text x="644" y="418" text-anchor="middle" font-size="11" fill="currentColor" stroke="none">Project home</text>
</svg>

## 3 · Project home & tools

Each project enables a set of tools, shown as tabs; the team toggles them in project settings. See: [Project tools](/docs/project-tools), [Projects](/docs/projects).

<svg viewBox="0 0 760 230" width="100%" role="img" aria-label="Project home and tools, three screens. Screen one, the project home with an active Docs tab and two more available tabs. An arrow labelled open settings leads to screen two, the Tools settings, a checklist with Docs enabled and Messages and Files available. An arrow labelled Save leads back to screen three, the project home now showing a newly enabled Messages tab highlighted." fill="none" stroke="currentColor" font-family="ui-sans-serif, system-ui, sans-serif">
  <defs><marker id="flowarrow-3" markerWidth="9" markerHeight="9" refX="6.5" refY="3" orient="auto"><path d="M0,0 L8,3 L0,6 z" fill="currentColor" stroke="none"/></marker></defs>

  <!-- Screen 1: Project home (x=16) -->
  <rect x="16" y="40" width="200" height="140" rx="12" stroke-width="1.5"/>
  <line x1="16" y1="64" x2="216" y2="64" stroke-width="1"/>
  <circle cx="30" cy="52" r="3" stroke-width="1"/><circle cx="42" cy="52" r="3" stroke-width="1"/><circle cx="54" cy="52" r="3" stroke-width="1"/>
  <rect x="70" y="46" width="132" height="12" rx="6" stroke-width="1" opacity="0.5"/>
  <rect x="36" y="78" width="90" height="8" rx="4" fill="currentColor" stroke="none" opacity="0.4"/>
  <rect class="text-accent" x="36" y="94" width="40" height="15" rx="4" stroke-width="2"/>
  <text class="text-accent" x="56" y="104.5" text-anchor="middle" font-size="8" font-weight="700" fill="currentColor" stroke="none">Docs</text>
  <rect x="80" y="94" width="40" height="15" rx="4" stroke-width="1" opacity="0.55"/>
  <rect x="124" y="94" width="40" height="15" rx="4" stroke-width="1" opacity="0.55"/>
  <rect x="36" y="120" width="160" height="6" rx="3" fill="currentColor" stroke="none" opacity="0.16"/>
  <rect x="36" y="132" width="130" height="6" rx="3" fill="currentColor" stroke="none" opacity="0.16"/>
  <rect x="36" y="144" width="150" height="6" rx="3" fill="currentColor" stroke="none" opacity="0.16"/>

  <!-- Screen 2: Tools settings (x=280) -->
  <rect x="280" y="40" width="200" height="140" rx="12" stroke-width="1.5"/>
  <line x1="280" y1="64" x2="480" y2="64" stroke-width="1"/>
  <circle cx="294" cy="52" r="3" stroke-width="1"/><circle cx="306" cy="52" r="3" stroke-width="1"/><circle cx="318" cy="52" r="3" stroke-width="1"/>
  <rect x="334" y="46" width="132" height="12" rx="6" stroke-width="1" opacity="0.5"/>
  <rect x="300" y="78" width="60" height="8" rx="4" fill="currentColor" stroke="none" opacity="0.4"/>
  <rect class="text-accent" x="300" y="96" width="11" height="11" rx="3" stroke-width="1.25"/>
  <path class="text-accent" d="M302.5,101.5 L304.5,104 L308.5,99" stroke-width="1.5"/>
  <rect x="317" y="99" width="120" height="5" rx="2.5" fill="currentColor" stroke="none" opacity="0.3"/>
  <rect x="300" y="114" width="11" height="11" rx="3" stroke-width="1.25" opacity="0.7"/>
  <rect x="317" y="117" width="100" height="5" rx="2.5" fill="currentColor" stroke="none" opacity="0.22"/>
  <rect x="300" y="132" width="11" height="11" rx="3" stroke-width="1.25" opacity="0.7"/>
  <rect x="317" y="135" width="90" height="5" rx="2.5" fill="currentColor" stroke="none" opacity="0.22"/>
  <rect class="text-accent" x="300" y="152" width="70" height="18" rx="5" stroke-width="2.25"/>
  <text class="text-accent" x="335" y="164.5" text-anchor="middle" font-size="9" font-weight="700" fill="currentColor" stroke="none">Save</text>

  <!-- Screen 3: Home updated (x=544) -->
  <rect x="544" y="40" width="200" height="140" rx="12" stroke-width="1.5"/>
  <line x1="544" y1="64" x2="744" y2="64" stroke-width="1"/>
  <circle cx="558" cy="52" r="3" stroke-width="1"/><circle cx="570" cy="52" r="3" stroke-width="1"/><circle cx="582" cy="52" r="3" stroke-width="1"/>
  <rect x="598" y="46" width="132" height="12" rx="6" stroke-width="1" opacity="0.5"/>
  <rect x="564" y="78" width="90" height="8" rx="4" fill="currentColor" stroke="none" opacity="0.4"/>
  <rect x="564" y="94" width="40" height="15" rx="4" stroke-width="1" opacity="0.55"/>
  <text x="584" y="104.5" text-anchor="middle" font-size="8" fill="currentColor" stroke="none" opacity="0.6">Docs</text>
  <rect class="text-accent" x="608" y="94" width="58" height="15" rx="4" stroke-width="2"/>
  <text class="text-accent" x="637" y="104.5" text-anchor="middle" font-size="8" font-weight="700" fill="currentColor" stroke="none">Messages</text>
  <rect x="564" y="120" width="160" height="6" rx="3" fill="currentColor" stroke="none" opacity="0.16"/>
  <rect x="564" y="132" width="130" height="6" rx="3" fill="currentColor" stroke="none" opacity="0.16"/>
  <rect x="564" y="144" width="150" height="6" rx="3" fill="currentColor" stroke="none" opacity="0.16"/>

  <!-- Connectors -->
  <path d="M216 110 H278" stroke-width="1.5" marker-end="url(#flowarrow-3)"/>
  <text x="247" y="104" text-anchor="middle" font-size="9.5" fill="currentColor" stroke="none" opacity="0.6">open settings</text>
  <path d="M480 110 H542" stroke-width="1.5" marker-end="url(#flowarrow-3)"/>
  <text x="511" y="104" text-anchor="middle" font-size="9.5" fill="currentColor" stroke="none" opacity="0.6">Save</text>

  <!-- Captions -->
  <text x="116" y="198" text-anchor="middle" font-size="11" fill="currentColor" stroke="none">Project home</text>
  <text x="380" y="198" text-anchor="middle" font-size="11" fill="currentColor" stroke="none">Settings · Tools</text>
  <text x="644" y="198" text-anchor="middle" font-size="11" fill="currentColor" stroke="none">Home reflects the toggle</text>
</svg>
