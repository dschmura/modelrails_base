---
title: Getting Started
description: Setup instructions and development workflow for ModelRails
keywords: setup install mise ruby bundle rspec tests oauth credentials development favicon icons branding
---

# Getting Started

## Prerequisites

- [mise](https://mise.jdx.dev/) for runtime version management (see `.tool-versions`)
- Chromium (installed by Playwright for system tests)

## Setup

```bash
mise install        # Install Ruby and Node from .tool-versions
bin/setup           # Install deps, prepare database, start server
```

Or step by step:

```bash
bundle install
rails db:prepare
rails db:seed       # Seeds default roles
bin/dev             # Start development server
```

## Running Tests

```bash
bundle exec rspec                        # Full suite
bundle exec rspec --format documentation # Verbose output
```

Coverage report is generated at `coverage/index.html`.

## Key Commands

| Command | Purpose |
|---------|---------|
| `bin/dev` | Start development server |
| `bundle exec rspec` | Run test suite |
| `bundle exec brakeman` | Security scan |
| `rails users:unlock[email]` | Unlock a locked account |
| `rails users:verify[email]` | Manually verify an email |
| `rails users:suspend[email]` | Suspend a user |

## Favicon and PWA Icons

The app ships with a multi-format favicon setup in `public/`:

| File | Purpose |
|------|---------|
| `favicon.ico` | Legacy browsers (any size) |
| `icon.svg` | Modern browsers (scalable, crisp at all sizes) |
| `apple-touch-icon.png` | iOS home screen bookmark |
| `icon-192.png` | PWA icon (192x192) |
| `icon-512.png` | PWA icon and splash screen (512x512) |
| `manifest.webmanifest` | PWA manifest (app name, icons, theme) |

These are referenced in both `app/views/layouts/application.html.erb` and `app/views/layouts/markdowndocs/application.html.erb` via link tags in `<head>`.

To replace with your own branding, swap the files in `public/` keeping the same filenames and sizes. Update `name` and `short_name` in `manifest.webmanifest` to match your app name.

## OAuth Setup

Add credentials for Google and GitHub OAuth:

```bash
bin/rails credentials:edit
```

```yaml
google:
  client_id: your_id
  client_secret: your_secret
github:
  client_id: your_id
  client_secret: your_secret
```
