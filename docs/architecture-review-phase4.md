# ModelRails Architecture Review — Phase 4 Design Validation

**Date:** 2026-03-26
**Purpose:** Validate the workspace + project architecture against real-world application scenarios

---

## 1. Core Data Model

### Entity Relationship Diagram

```mermaid
erDiagram
    User ||--o{ Membership : "has many"
    User ||--o{ ProjectMembership : "has many"
    User ||--o{ Invitation : "invited_by"
    User ||--|| Workspace : "personal workspace"

    Workspace ||--o{ Membership : "has many"
    Workspace ||--o{ Project : "has many"
    Workspace ||--o{ Invitation : "invitable (polymorphic)"
    Workspace ||--o{ Role : "custom roles"

    Role ||--o{ Membership : "assigned via"

    Membership }o--|| User : "belongs to"
    Membership }o--|| Workspace : "belongs to"
    Membership }o--|| Role : "belongs to"

    Project ||--o{ ProjectMembership : "has many"
    Project ||--o{ Invitation : "invitable (polymorphic)"
    Project }o--|| Workspace : "belongs to"
    Project }o--|| User : "created_by"

    ProjectMembership }o--|| Project : "belongs to"
    ProjectMembership }o--|| User : "belongs to"

    Invitation }o--|| Role : "assigned role"
    Invitation }o--|| User : "invited_by"

    User {
        string email_address
        string first_name
        string last_name
        string password_digest
    }

    Workspace {
        string name
        string slug
        string plan
        int max_members
        int max_projects
        string primary_color
        datetime discarded_at
    }

    Membership {
        int user_id FK
        int workspace_id FK
        int role_id FK
        datetime discarded_at
    }

    Role {
        string name
        string slug
        json permissions
        int workspace_id FK
    }

    Project {
        int workspace_id FK
        string name
        string slug
        text description
        int created_by_id FK
        string primary_color
        datetime discarded_at
    }

    ProjectMembership {
        int project_id FK
        int user_id FK
        string role
        boolean pinned
    }

    Invitation {
        string invitable_type
        int invitable_id
        string email
        string token
        int role_id FK
        int invited_by_id FK
        string status
        datetime expires_at
    }
```

### Conceptual Hierarchy

```mermaid
graph TD
    U[User] -->|auto-created on signup| PW[Personal Workspace]
    U -->|invited to| OW[Organization Workspace]

    PW -->|contains| PP[Personal Projects]
    OW -->|contains| OP[Organization Projects]

    PP -->|shared via| PI1[Project Invitation]
    OP -->|members added| DA[Direct Add from workspace]
    OP -->|external users via| PI2[Project Invitation]

    PI1 -->|auto-adds to| PW
    PI2 -->|auto-adds to| OW

    style PW fill:#e0f2fe,stroke:#0284c7
    style OW fill:#f0fdf4,stroke:#16a34a
    style PP fill:#e0f2fe,stroke:#0284c7
    style OP fill:#f0fdf4,stroke:#16a34a
```

### Authorization Model

```mermaid
graph LR
    subgraph Workspace Level
        WR[Role Model + Permissions JSON]
        WR --> WO[Owner: manage_workspace, manage_members, manage_teams, manage_settings]
        WR --> WA[Admin: manage_members, manage_teams, manage_settings]
        WR --> WM[Member: manage_teams]
        WR --> WV[Viewer: no permissions]
    end

    subgraph Project Level
        PR[Enum on ProjectMembership]
        PR --> PC[Creator: manage project + members]
        PR --> PE[Editor: create + edit content]
        PR --> PV[Viewer: read-only]
    end

    WR -.->|"Forker can add custom roles\nwith custom permissions"| CR[Custom Role]
    PR -.->|"Upgrade path: migrate\nenum to Role reference"| URR[Role Reference]

    style WR fill:#fef3c7,stroke:#d97706
    style PR fill:#e0f2fe,stroke:#0284c7
```

### Invitation Flow

```mermaid
sequenceDiagram
    participant C as Creator/Owner
    participant App as ModelRails
    participant M as Mailer
    participant I as Invitee

    alt Workspace Invitation
        C->>App: Invite email to workspace (with role)
        App->>M: Send invitation email
        M->>I: Email with accept/decline links
        I->>App: Click accept
        alt Existing user
            App->>App: Create Membership
        else New user
            App->>I: Redirect to registration
            I->>App: Register
            App->>App: Create Membership (auto-join)
        end
    end

    alt Project Invitation
        C->>App: Invite email to project (with role)
        App->>M: Send invitation email
        M->>I: Email with accept/decline links
        I->>App: Click accept
        App->>App: Create Membership (workspace) if needed
        App->>App: Create ProjectMembership
    end
```

---

## 2. Key Design Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| **Workspace** | Organizational boundary | Billing, roles, permissions, member management |
| **Project** | Collaboration boundary | Who works together on what, ad-hoc, purpose-driven |
| **Personal workspace** | Auto-created on sign-up | Individual users get a home without organizational friction |
| **Workspace roles** | Role model + permissions JSON | Forker-extensible via seeds, Pundit checks permission strings |
| **Project roles** | Enum (creator/editor/viewer) | Simple, clear mental model. Documented upgrade path to Role model |
| **Project invitations** | Polymorphic, auto-adds to workspace | One-step sharing, no "join org first" friction |
| **Soft delete** | Discardable concern (discarded_at) | One pattern everywhere, simple concern |
| **Cascade** | Workspace membership discard → destroy project memberships | Direct method call in deactivate!, no callback framework |

---

## 3. Scenario Validation

### Scenario 1: SonicPics — Individual User

**Context:** Dan signs up to make vacation slideshows. Wants to share with his wife.

```mermaid
graph TD
    D[Dan signs up] --> PW["Personal Workspace<br/>(auto-created, invisible)"]
    PW --> P["Project: My Great Vacation<br/>Dan = Creator"]
    P -->|project invitation| W["Wife accepts invite"]
    W --> WM["Wife → Workspace Member"]
    W --> PM["Wife → Project Editor"]

    style PW fill:#e0f2fe,stroke:#0284c7
    style P fill:#fef3c7,stroke:#d97706
```

| Step | Works? |
|------|--------|
| Sign up → auto workspace | Yes |
| Create project | Yes |
| Share with wife (project invitation) | Yes |
| Wife edits slideshow | Yes (editor role) |

**Gaps:** None for this scenario.

---

### Scenario 2: SonicPics — School/Enterprise

**Context:** Lincoln Elementary purchases a license. Teachers create class projects.

```mermaid
graph TD
    A[District Admin] --> W["Workspace: Lincoln Elementary<br/>plan: enterprise, max_members: 200"]
    W -->|batch invite| T["Teachers (member role)"]
    W -->|batch invite| S["Students (viewer role)"]
    T -->|creates| P1["Project: 3rd Grade Hour 2"]
    T -->|adds students| P1
    S -->|added as editors| P1

    style W fill:#f0fdf4,stroke:#16a34a
    style P1 fill:#fef3c7,stroke:#d97706
```

| Step | Works? |
|------|--------|
| District creates workspace | Yes |
| Batch invite teachers/students | Yes |
| Teacher creates project | Yes |
| Students collaborate | Yes (editor role) |
| Student submits to teacher | No (resource-level, deferred) |
| Student shares with classmate | No (resource-level, deferred) |

**Gaps:** Resource management and submission workflows (deferred to post-Phase 5).

---

### Scenario 3: Consulting Firm

**Context:** Acme Consulting manages client engagements with external client contacts.

```mermaid
graph TD
    P[Partner] --> W["Workspace: Acme Consulting"]
    W -->|admin role| Mgr[Managers]
    W -->|member role| An[Analysts]
    Mgr -->|creates| Proj["Project: Client X Tax Audit"]
    Proj -->|direct add| An
    Proj -->|project invitation| CC["Client Contact"]
    CC --> WV["Auto-added to workspace as viewer"]
    CC --> PV["Added to project as viewer"]

    style W fill:#f0fdf4,stroke:#16a34a
    style Proj fill:#fef3c7,stroke:#d97706
    style CC fill:#fef9c3,stroke:#ca8a04
```

| Step | Works? |
|------|--------|
| Create workspace | Yes |
| Invite staff with roles | Yes |
| Create project | Yes |
| Add client as viewer | Yes (project invitation) |
| Client sees only their project | Yes (project membership scopes access) |
| Client isolated from other workspace data | Partial (they're a workspace viewer) |

**Gaps:** External guest isolation — client can see workspace member list. Forker can restrict with a "guest" workspace role that has no workspace-level permissions.

---

### Scenario 4: Classroom Database (University)

**Context:** Room/equipment directory. Everyone can browse, departments manage their buildings.

```mermaid
graph TD
    IT[IT Admin] --> W["Workspace: State University"]
    W -->|viewer role| All["All Staff/Students/Alumni"]
    W -->|member role| Dept["Department Admins"]
    Dept -->|creates| B1["Project: Engineering Building"]
    Dept -->|editor role| RM["Room Managers"]
    All -.->|"policy tweak: show? = any workspace member"| B1

    style W fill:#f0fdf4,stroke:#16a34a
    style B1 fill:#fef3c7,stroke:#d97706
```

| Step | Works? |
|------|--------|
| University workspace | Yes |
| Bulk member add | Yes |
| Department creates building project | Yes |
| Room managers edit | Yes (editor role) |
| Everyone can browse | One-line policy change (`show?` → `membership.present?`) |

**Gaps:** One policy line change for public-within-workspace projects.

---

### Scenario 5: Convene (Conference App)

**Context:** AwesomeConf 2026 with 500 attendees, sessions, bio sharing.

```mermaid
graph TD
    O[Organizer] --> W["Workspace: AwesomeConf 2026<br/>max_members: 500"]
    W -->|batch invite 500| A["Attendees (member role)"]
    O -->|creates| S1["Project: AI Track"]
    O -->|creates| S2["Project: Web Track"]
    O -->|creates| S3["Project: Keynotes"]
    A -.->|"policy tweak: self-join"| S1
    A -.->|"policy tweak: self-join"| S2

    style W fill:#f0fdf4,stroke:#16a34a
    style S1 fill:#fef3c7,stroke:#d97706
    style S2 fill:#fef3c7,stroke:#d97706
    style S3 fill:#fef3c7,stroke:#d97706
```

| Step | Works? |
|------|--------|
| Create conference workspace | Yes |
| Batch invite attendees | Yes |
| Create session tracks as projects | Yes |
| Attendees join sessions | Policy tweak (self-add to open projects) |
| Bio card creation/sharing | No (resource-level, deferred) |
| Schedule = list of projects you're in | Derivable from project memberships (view concern) |

**Gaps:** Self-join (policy tweak). Bio/profile sharing (deferred).

---

### Scenario 6: Creative Agency

**Context:** Agency manages campaigns for clients.

| Step | Works? |
|------|--------|
| Agency workspace | Yes |
| Campaign projects | Yes |
| Client as viewer | Yes (project invitation) |
| "Can comment but not edit" | No (resource-level permission, deferred) |

---

### Scenario 7: Open Source Project

**Context:** Organization with repos/initiatives.

| Step | Works? |
|------|--------|
| Organization workspace | Yes |
| Repo/initiative projects | Yes |
| Maintainer/Contributor/Triager roles | Enum names don't match, but permissions do |
| Custom role names | I18n customization (easy) or Role model upgrade (documented) |

---

## 4. What Phase 4 Delivers

### Included

1. **Project model** — Tenanted, Discardable, slug, logo + OKLCH color, max_projects enforcement
2. **ProjectMembership** — enum roles (creator/editor/viewer), pinned boolean
3. **Personal workspace** — auto-created on User sign-up
4. **Project-level invitations** — polymorphic Invitation reuse, auto-adds to workspace
5. **Pundit policies** — permission checks via enum, workspace owner can delete any project
6. **Rename** max_teams → max_projects
7. **Cascade** — workspace membership discard destroys project memberships

### Forker's Job (Not Starter Kit)

- External guest isolation (project-only access)
- Self-join for open projects (policy tweak)
- Public-within-workspace projects (policy tweak)
- Custom project role names (I18n or Role model upgrade)
- Resource-level sharing/commenting/submission workflows
- All resource types (documents, links, notes, etc.)

### Documented Upgrade Path

- **Enum → Role model for project roles:** Migration adds `role_id` to `project_memberships`, seeds custom roles, updates policies. Documented in README.

---

## 5. Phase Summary (All Phases)

```mermaid
gantt
    title ModelRails Build Phases
    dateFormat YYYY-MM-DD
    section Phase 1
        Auth + Users + Static Pages           :done, p1, 2026-03-25, 1d
    section Phase 2
        Workspaces + Multi-tenancy + Branding :done, p2, after p1, 1d
    section Phase 3
        Invitations + Membership Lifecycle    :done, p3, after p2, 1d
    section Phase 4
        Projects + Collaboration Spaces       :active, p4, after p3, 1d
    section Phase 5
        Admin Tasks + Docs + Activity + Polish :p5, after p4, 1d
```

| Phase | Tag | Examples | Coverage |
|-------|-----|----------|----------|
| 1 — Auth + Users | v0.1.0 | 77 | 89% |
| 2 — Workspaces | v0.2.0 | 133 | 89.7% |
| 3 — Invitations | v0.3.0 | 217 | 92.3% |
| 4 — Projects | v0.4.0 | TBD | TBD |
| 5 — Admin/Polish | v0.5.0 | TBD | TBD |
