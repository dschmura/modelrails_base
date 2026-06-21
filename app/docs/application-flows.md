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
