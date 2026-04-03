# File-Based Icon Helper System Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a file-based icon system with an `icon(:name)` helper backed by a Nokogiri-powered registry that loads SVGs from `app/assets/icons/`, so downstream projects can customize icons by replacing files.

**Architecture:** `IconRegistry` singleton loads and caches SVG files from `app/assets/icons/{outline,solid}/`. `IconHelper` provides the `icon()` method that looks up parsed SVG data from the registry and renders `<svg>` tags via `tag.svg`. An initializer eager-loads icons in production.

**Tech Stack:** Rails 8.1, Nokogiri (built-in Rails dependency), RSpec

**Spec:** `docs/superpowers/specs/2026-04-02-icon-system-design.md`

---

## File Structure

| File | Action | Responsibility |
| ---- | ------ | -------------- |
| `app/lib/icon_registry.rb` | Create | Load, parse, cache SVG files |
| `app/helpers/icon_helper.rb` | Create | `icon()` helper method |
| `config/initializers/icons.rb` | Create | Eager-load in production |
| `app/assets/icons/outline/*.svg` | Create | Starter Heroicon set (11 icons) |
| `app/assets/icons/solid/x_mark.svg` | Create | Solid X mark variant |
| `spec/lib/icon_registry_spec.rb` | Create | Registry unit specs |
| `spec/helpers/icon_helper_spec.rb` | Create | Helper unit specs |

---

### Task 1: Create Starter SVG Icon Files

**Files:**

- Create: `app/assets/icons/outline/check_circle.svg`
- Create: `app/assets/icons/outline/information_circle.svg`
- Create: `app/assets/icons/outline/exclamation_triangle.svg`
- Create: `app/assets/icons/outline/exclamation_circle.svg`
- Create: `app/assets/icons/outline/x_mark.svg`
- Create: `app/assets/icons/outline/bars_3.svg`
- Create: `app/assets/icons/outline/chevron_down.svg`
- Create: `app/assets/icons/outline/sun.svg`
- Create: `app/assets/icons/outline/moon.svg`
- Create: `app/assets/icons/outline/computer_desktop.svg`
- Create: `app/assets/icons/outline/envelope.svg`
- Create: `app/assets/icons/solid/x_mark.svg`

- [ ] **Step 1: Create the icon directories**

```bash
mkdir -p app/assets/icons/outline app/assets/icons/solid
```

- [ ] **Step 2: Create outline/check_circle.svg**

```xml
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5">
  <path stroke-linecap="round" stroke-linejoin="round" d="M9 12.75 11.25 15 15 9.75M21 12a9 9 0 1 1-18 0 9 9 0 0 1 18 0Z" />
</svg>
```

- [ ] **Step 3: Create outline/information_circle.svg**

```xml
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5">
  <path stroke-linecap="round" stroke-linejoin="round" d="m11.25 11.25.041-.02a.75.75 0 0 1 1.063.852l-.708 2.836a.75.75 0 0 0 1.063.853l.041-.021M21 12a9 9 0 1 1-18 0 9 9 0 0 1 18 0Zm-9-3.75h.008v.008H12V8.25Z" />
</svg>
```

- [ ] **Step 4: Create outline/exclamation_triangle.svg**

```xml
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5">
  <path stroke-linecap="round" stroke-linejoin="round" d="M12 9v3.75m-9.303 3.376c-.866 1.5.217 3.374 1.948 3.374h14.71c1.73 0 2.813-1.874 1.948-3.374L13.949 3.378c-.866-1.5-3.032-1.5-3.898 0L2.697 16.126ZM12 15.75h.007v.008H12v-.008Z" />
</svg>
```

- [ ] **Step 5: Create outline/exclamation_circle.svg**

```xml
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5">
  <path stroke-linecap="round" stroke-linejoin="round" d="M12 9v3.75m9-.75a9 9 0 1 1-18 0 9 9 0 0 1 18 0Zm-9 3.75h.008v.008H12v-.008Z" />
</svg>
```

- [ ] **Step 6: Create outline/x_mark.svg**

```xml
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5">
  <path stroke-linecap="round" stroke-linejoin="round" d="M6 18 18 6M6 6l12 12" />
</svg>
```

- [ ] **Step 7: Create outline/bars_3.svg**

```xml
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
  <path stroke-linecap="round" stroke-linejoin="round" d="M4 6h16M4 12h16M4 18h16" />
</svg>
```

- [ ] **Step 8: Create outline/chevron_down.svg**

```xml
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
  <path stroke-linecap="round" stroke-linejoin="round" d="M19 9l-7 7-7-7" />
</svg>
```

- [ ] **Step 9: Create outline/sun.svg**

```xml
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
  <path stroke-linecap="round" stroke-linejoin="round" d="M12 3v1m0 16v1m9-9h-1M4 12H3m15.364 6.364l-.707-.707M6.343 6.343l-.707-.707m12.728 0l-.707.707M6.343 17.657l-.707.707M16 12a4 4 0 11-8 0 4 4 0 018 0z" />
</svg>
```

- [ ] **Step 10: Create outline/moon.svg**

```xml
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
  <path stroke-linecap="round" stroke-linejoin="round" d="M20.354 15.354A9 9 0 018.646 3.646 9.003 9.003 0 0012 21a9.003 9.003 0 008.354-5.646z" />
</svg>
```

- [ ] **Step 11: Create outline/computer_desktop.svg**

```xml
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5">
  <path stroke-linecap="round" stroke-linejoin="round" d="M9 17.25v1.007a3 3 0 0 1-.879 2.122L7.5 21h9l-.621-.621A3 3 0 0 1 15 18.257V17.25m6-12V15a2.25 2.25 0 0 1-2.25 2.25H5.25A2.25 2.25 0 0 1 3 15V5.25A2.25 2.25 0 0 1 5.25 3h13.5A2.25 2.25 0 0 1 21 5.25Z" />
</svg>
```

- [ ] **Step 12: Create outline/envelope.svg**

```xml
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
  <path stroke-linecap="round" stroke-linejoin="round" d="M3 8l7.89 5.26a2 2 0 002.22 0L21 8M5 19h14a2 2 0 002-2V7a2 2 0 00-2-2H5a2 2 0 00-2 2v10a2 2 0 002 2z" />
</svg>
```

- [ ] **Step 13: Create solid/x_mark.svg**

```xml
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 20 20" fill="currentColor">
  <path d="M6.28 5.22a.75.75 0 0 0-1.06 1.06L8.94 10l-3.72 3.72a.75.75 0 1 0 1.06 1.06L10 11.06l3.72 3.72a.75.75 0 1 0 1.06-1.06L11.06 10l3.72-3.72a.75.75 0 0 0-1.06-1.06L10 8.94 6.28 5.22Z" />
</svg>
```

- [ ] **Step 14: Commit**

```bash
git add app/assets/icons/
git commit -m "feat: add starter Heroicon SVG set for icon system

11 outline icons and 1 solid icon covering toasts, navigation,
theme toggle, and email. Downstream projects customize by
replacing files in app/assets/icons/."
```

---

### Task 2: Create IconRegistry (TDD)

**Files:**

- Create: `spec/lib/icon_registry_spec.rb`
- Create: `app/lib/icon_registry.rb`

- [ ] **Step 1: Write the failing specs**

Create `spec/lib/icon_registry_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe IconRegistry do
  before { described_class.reload! }

  describe ".find" do
    it "returns parsed SVG data for a known outline icon" do
      result = described_class.find(:check_circle)
      expect(result[:inner_html]).to include("stroke-linecap")
      expect(result[:viewbox]).to eq("0 0 24 24")
      expect(result[:style]).to eq(:outline)
    end

    it "returns parsed SVG data for a known solid icon" do
      result = described_class.find(:x_mark, style: :solid)
      expect(result[:inner_html]).to include("<path")
      expect(result[:viewbox]).to eq("0 0 20 20")
      expect(result[:style]).to eq(:solid)
    end

    it "prefers outline when no style specified" do
      result = described_class.find(:x_mark)
      expect(result[:style]).to eq(:outline)
    end

    it "falls back to solid when outline not available" do
      # Create a temporary solid-only icon for this test
      solid_dir = Rails.root.join("app/assets/icons/solid")
      test_file = solid_dir.join("test_solid_only.svg")
      File.write(test_file, '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 20 20" fill="currentColor"><path d="M10 10z"/></svg>')
      described_class.reload!

      result = described_class.find(:test_solid_only)
      expect(result[:style]).to eq(:solid)
    ensure
      File.delete(test_file) if test_file&.exist?
      described_class.reload!
    end

    it "raises NotFound for unknown icons" do
      expect { described_class.find(:nonexistent_icon) }.to raise_error(IconRegistry::NotFound)
    end
  end

  describe ".exists?" do
    it "returns true for known icons" do
      expect(described_class.exists?(:check_circle)).to be true
    end

    it "returns false for unknown icons" do
      expect(described_class.exists?(:nonexistent_icon)).to be false
    end

    it "checks specific style when provided" do
      expect(described_class.exists?(:x_mark, style: :solid)).to be true
      expect(described_class.exists?(:check_circle, style: :solid)).to be false
    end
  end

  describe ".available_icons" do
    it "returns a sorted array of symbol names" do
      icons = described_class.available_icons
      expect(icons).to be_an(Array)
      expect(icons).to include(:check_circle, :x_mark, :sun, :moon)
      expect(icons).to eq(icons.sort)
    end

    it "deduplicates icons available in both styles" do
      icons = described_class.available_icons
      expect(icons.count(:x_mark)).to eq(1)
    end
  end

  describe ".reload!" do
    it "clears the cache" do
      described_class.find(:check_circle)
      described_class.reload!
      # After reload, should still work (reloads from disk)
      result = described_class.find(:check_circle)
      expect(result[:inner_html]).to include("stroke-linecap")
    end
  end

  describe "caching" do
    it "returns the same object on subsequent calls" do
      result1 = described_class.find(:check_circle)
      result2 = described_class.find(:check_circle)
      expect(result1).to equal(result2)
    end
  end
end
```

- [ ] **Step 2: Run specs to verify they fail**

Run: `bundle exec rspec spec/lib/icon_registry_spec.rb`
Expected: FAIL — `uninitialized constant IconRegistry`

- [ ] **Step 3: Create the IconRegistry**

Create `app/lib/icon_registry.rb`:

```ruby
class IconRegistry
  class NotFound < StandardError; end

  ICON_DIR = Rails.root.join("app/assets/icons")
  STYLES = %i[outline solid].freeze

  class << self
    def find(name, style: nil)
      name = name.to_sym
      if style
        cache[[name, style.to_sym]] || raise(NotFound, "Icon '#{name}' not found in #{style} style")
      else
        cache[[name, :outline]] || cache[[name, :solid]] || raise(NotFound, "Icon '#{name}' not found")
      end
    end

    def exists?(name, style: nil)
      name = name.to_sym
      if style
        cache.key?([name, style.to_sym])
      else
        cache.key?([name, :outline]) || cache.key?([name, :solid])
      end
    end

    def available_icons
      cache.keys.map(&:first).uniq.sort
    end

    def reload!
      @cache = nil
    end

    def eager_load!
      cache
    end

    private

    def cache
      @cache ||= load_all_icons
    end

    def load_all_icons
      icons = {}
      STYLES.each do |style|
        dir = ICON_DIR.join(style.to_s)
        next unless dir.exist?

        Dir.glob(dir.join("*.svg")).each do |path|
          name = File.basename(path, ".svg").to_sym
          icons[[name, style]] = parse_svg(path, style)
        end
      end
      icons
    end

    def parse_svg(path, style)
      doc = Nokogiri::XML(File.read(path))
      svg = doc.at_css("svg")
      {
        inner_html: svg.inner_html.strip,
        viewbox: svg["viewBox"],
        style: style
      }.freeze
    end
  end
end
```

- [ ] **Step 4: Run specs to verify they pass**

Run: `bundle exec rspec spec/lib/icon_registry_spec.rb`
Expected: 9 examples, 0 failures

- [ ] **Step 5: Commit**

```bash
git add app/lib/icon_registry.rb spec/lib/icon_registry_spec.rb
git commit -m "feat: add IconRegistry for file-based SVG loading

Loads SVGs from app/assets/icons/{outline,solid}/, parses with
Nokogiri to extract inner HTML and viewBox, caches results.
Prefers outline, falls back to solid."
```

---

### Task 3: Create IconHelper (TDD)

**Files:**

- Create: `spec/helpers/icon_helper_spec.rb`
- Create: `app/helpers/icon_helper.rb`

- [ ] **Step 1: Write the failing specs**

Create `spec/helpers/icon_helper_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe IconHelper do
  before { IconRegistry.reload! }

  describe "#icon" do
    it "renders an svg element" do
      result = helper.icon(:check_circle)
      expect(result).to have_css("svg")
    end

    it "includes the SVG inner paths" do
      result = helper.icon(:check_circle)
      expect(result).to have_css("svg path")
    end

    it "sets the correct viewBox" do
      result = helper.icon(:check_circle)
      expect(result).to have_css('svg[viewBox="0 0 24 24"]')
    end

    describe "sizes" do
      it "applies xs size classes" do
        result = helper.icon(:check_circle, size: :xs)
        expect(result).to have_css("svg.w-3.h-3")
      end

      it "applies sm size classes" do
        result = helper.icon(:check_circle, size: :sm)
        expect(result).to have_css("svg.w-4.h-4")
      end

      it "applies md size classes by default" do
        result = helper.icon(:check_circle)
        expect(result).to have_css("svg.w-5.h-5")
      end

      it "applies lg size classes" do
        result = helper.icon(:check_circle, size: :lg)
        expect(result).to have_css("svg.w-6.h-6")
      end
    end

    describe "styles" do
      it "sets outline attributes by default" do
        result = helper.icon(:check_circle)
        expect(result).to have_css('svg[fill="none"][stroke="currentColor"]')
      end

      it "sets solid attributes when requested" do
        result = helper.icon(:x_mark, style: :solid)
        expect(result).to have_css('svg[fill="currentColor"]')
        expect(result).not_to have_css("svg[stroke]")
      end
    end

    describe "custom classes" do
      it "merges custom classes with size classes" do
        result = helper.icon(:check_circle, class: "text-success-icon")
        expect(result).to have_css("svg.w-5.h-5.text-success-icon")
      end

      it "omits size classes when custom class includes w-* and h-*" do
        result = helper.icon(:check_circle, class: "w-8 h-8 text-info")
        expect(result).to have_css("svg.w-8.h-8.text-info")
        expect(result).not_to have_css("svg.w-5")
      end
    end

    describe "accessibility" do
      it "is decorative by default with aria-hidden" do
        result = helper.icon(:check_circle)
        expect(result).to have_css('svg[aria-hidden="true"]')
        expect(result).not_to have_css("svg[role]")
      end

      it "is meaningful when aria_label is provided" do
        result = helper.icon(:check_circle, aria_label: "Success")
        expect(result).to have_css('svg[role="img"][aria-label="Success"]')
        expect(result).not_to have_css("svg[aria-hidden]")
      end
    end

    describe "additional attributes" do
      it "passes data attributes through" do
        result = helper.icon(:sun, data: { theme_toggle_target: "lightIcon" })
        expect(result).to have_css('svg[data-theme-toggle-target="lightIcon"]')
      end
    end

    describe "unknown icons" do
      it "raises IconRegistry::NotFound" do
        expect { helper.icon(:nonexistent) }.to raise_error(IconRegistry::NotFound)
      end
    end
  end
end
```

- [ ] **Step 2: Run specs to verify they fail**

Run: `bundle exec rspec spec/helpers/icon_helper_spec.rb`
Expected: FAIL — `uninitialized constant IconHelper` or `undefined method 'icon'`

- [ ] **Step 3: Create the IconHelper**

Create `app/helpers/icon_helper.rb`:

```ruby
module IconHelper
  SIZES = {
    xs: "w-3 h-3",
    sm: "w-4 h-4",
    md: "w-5 h-5",
    lg: "w-6 h-6"
  }.freeze

  def icon(name, size: :md, style: :outline, aria_label: nil, **attrs)
    data = IconRegistry.find(name, style: style)
    custom_class = attrs.delete(:class)

    size_classes = custom_sizing?(custom_class) ? "" : SIZES.fetch(size)
    css_class = [size_classes, custom_class].compact_blank.join(" ")

    svg_attrs = {
      viewBox: data[:viewbox],
      class: css_class,
      xmlns: "http://www.w3.org/2000/svg"
    }

    if data[:style] == :outline
      svg_attrs[:fill] = "none"
      svg_attrs[:stroke] = "currentColor"
    else
      svg_attrs[:fill] = "currentColor"
    end

    if aria_label
      svg_attrs[:role] = "img"
      svg_attrs[:"aria-label"] = aria_label
    else
      svg_attrs[:"aria-hidden"] = "true"
    end

    svg_attrs.merge!(attrs)

    tag.svg(**svg_attrs) { data[:inner_html].html_safe }
  end

  private

  def custom_sizing?(css_class)
    return false unless css_class

    css_class.match?(/\bw-\S+/) && css_class.match?(/\bh-\S+/)
  end
end
```

- [ ] **Step 4: Run specs to verify they pass**

Run: `bundle exec rspec spec/helpers/icon_helper_spec.rb`
Expected: 12 examples, 0 failures

- [ ] **Step 5: Commit**

```bash
git add app/helpers/icon_helper.rb spec/helpers/icon_helper_spec.rb
git commit -m "feat: add icon() helper with size, style, and accessibility support

Renders SVGs from IconRegistry with configurable size presets,
outline/solid styles, aria-hidden (decorative) or role=img
(meaningful), and custom class/attribute pass-through."
```

---

### Task 4: Add Production Initializer

**Files:**

- Create: `config/initializers/icons.rb`

- [ ] **Step 1: Create the initializer**

Create `config/initializers/icons.rb`:

```ruby
Rails.application.config.after_initialize do
  IconRegistry.eager_load! if Rails.application.config.eager_load
end
```

- [ ] **Step 2: Verify icons load in development**

Run: `bundle exec rails runner "puts IconRegistry.available_icons.inspect"`
Expected: Prints array of icon symbols including `:check_circle`, `:sun`, `:x_mark`, etc.

- [ ] **Step 3: Commit**

```bash
git add config/initializers/icons.rb
git commit -m "feat: add icons initializer for production eager loading

Calls IconRegistry.eager_load! when eager_load is true (production).
In development, icons are lazy-loaded on first access."
```

---

### Task 5: Run Full Test Suite

**Files:** None (verification only)

- [ ] **Step 1: Run the full test suite**

Run: `bundle exec rspec`
Expected: All specs pass (680+), 0 failures.

- [ ] **Step 2: Verify icon helper works in a view context**

Run: `bundle exec rails runner "include IconHelper; include ActionView::Helpers::TagHelper; include ActionView::Context; puts icon(:check_circle, size: :sm, class: 'text-success-icon')"`
Expected: Prints an `<svg>` tag with `class="w-4 h-4 text-success-icon"`, `viewBox="0 0 24 24"`, `fill="none"`, `stroke="currentColor"`, `aria-hidden="true"`, and the check circle path data.

---

## Verification

After all tasks are complete:

1. **Full suite:** `bundle exec rspec` — all specs green
2. **Registry:** `bundle exec rails runner "puts IconRegistry.available_icons.inspect"` — shows all 11 icons
3. **Helper rendering:** Verify `icon(:check_circle)` produces valid SVG markup
4. **Sizes:** Verify each size preset produces correct Tailwind classes
5. **Styles:** Verify outline vs solid produces correct fill/stroke attributes
6. **Accessibility:** Verify decorative (aria-hidden) vs meaningful (role=img) behavior
7. **Custom classes:** Verify custom w-/h- classes override size presets
