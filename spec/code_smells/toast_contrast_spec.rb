# frozen_string_literal: true

require "rails_helper"

# Toast icons meet the 3:1 non-text floor (WCAG 1.4.11), computed from the
# shipped token values rather than eyeballed (#1236).
#
# Nothing else can see this. **axe measures TEXT contrast only** — it has no
# non-text rule — so neither the AAA gate here nor the gem's render tests can
# tell whether an icon is visible on the surface it sits on. That blind spot is
# how the signal chip borders sat under the floor until they were measured by
# hand (modelrails_ui#257), and how a success toast shipped at 1.32:1.
#
# The pill is the reason this is subtle: `--color-surface-toast` INVERTS
# (neutral-900 in the light theme, neutral-100 in the dark one), so a token
# tuned for the page's own ground is wrong on it by construction. The text
# already had `--color-text-on-toast` for that; the icon did not.
RSpec.describe "Code smell: toast icons clear the non-text contrast floor" do
  # `let`, not a constant: SCREAMING_CASE in a describe block lands on Object
  # and collides across parallel workers (#607).
  let(:non_text_floor) { 3.0 }

  let(:signals)  { File.read(Rails.root.join("app/assets/tailwind/tokens/_signals.css")) }
  let(:semantic) { File.read(Rails.root.join("app/assets/tailwind/tokens/_semantic.css")) }

  # :root block first, .dark second — the order they appear in each file.
  def token(css, name, theme)
    values = css.scan(/--color-#{Regexp.escape(name)}:\s*oklch\(\s*([\d.]+)%\s+([\d.]+)\s+([\d.]+)/)
    raise "no --color-#{name} in that stylesheet" if values.empty?

    values.fetch(theme == :light ? 0 : 1).map(&:to_f)
  end

  def srgb(lch)
    l, c, h = lch
    l /= 100.0
    rad = h * Math::PI / 180
    a, b = c * Math.cos(rad), c * Math.sin(rad)
    lms = [ l + 0.3963377774 * a + 0.2158037573 * b,
            l - 0.1055613458 * a - 0.0638541728 * b,
            l - 0.0894841775 * a - 1.2914855480 * b ].map { |v| v**3 }
    linear = [ 4.0767416621 * lms[0] - 3.3077115913 * lms[1] + 0.2309699292 * lms[2],
               -1.2684380046 * lms[0] + 2.6097574011 * lms[1] - 0.3413193965 * lms[2],
               -0.0041960863 * lms[0] - 0.7034186147 * lms[1] + 1.7076147010 * lms[2] ]
    linear.map { |v| v.clamp(0.0, 1.0) }
  end

  def luminance(rgb)
    r, g, b = rgb
    (0.2126 * r) + (0.7152 * g) + (0.0722 * b)
  end

  def contrast(fg, bg)
    a, b = luminance(fg), luminance(bg)
    ((([ a, b ].max) + 0.05) / (([ a, b ].min) + 0.05)).round(2)
  end

  # The pill is 90% opaque, so what an eye sees is the composite over the page.
  # Measuring the raw token would flatter it.
  def over(fg, alpha, bg)
    fg.each_with_index.map { |v, i| (v * alpha) + (bg[i] * (1 - alpha)) }
  end

  def page(theme)
    theme == :light ? srgb([ 98.4, 0.003, 247.858 ]) : srgb([ 20.8, 0.042, 265.755 ])
  end

  def pill(theme)
    raw = theme == :light ? [ 20.5, 0.016, 265.755 ] : [ 96.8, 0.007, 264.536 ]
    over(srgb(raw), 0.90, page(theme))
  end

  # A ratio computation that cannot fail is worth nothing: pin it against a
  # pair whose answer is known independently.
  it "computes a contrast ratio correctly" do
    white, black = [ 1.0, 1.0, 1.0 ], [ 0.0, 0.0, 0.0 ]

    expect(contrast(white, black)).to be_within(0.01).of(21.0)
    expect(contrast(white, white)).to be_within(0.01).of(1.0)
  end

  %i[light dark].each do |theme|
    it "keeps the #{theme}-theme pill's icons visible on the inverted surface" do
      %w[info success].each do |tone|
        icon = srgb(token(semantic, "#{tone}-icon-on-toast", theme))
        ratio = contrast(icon, pill(theme))

        expect(ratio).to be >= non_text_floor,
          "#{theme} #{tone} toast icon is #{ratio}:1 on the pill, under the #{non_text_floor}:1 " \
          "non-text floor. The pill inverts; the icon token has to invert with it."
      end
    end

    it "keeps the #{theme}-theme card's icons visible on their own signal surface" do
      %w[warning danger].each do |tone|
        # The card's icon takes the tone's TEXT token, as the gem's alert does.
        icon = srgb(token(signals, tone, theme))
        ratio = contrast(icon, srgb(token(signals, "#{tone}-surface", theme)))

        expect(ratio).to be >= non_text_floor,
          "#{theme} #{tone} toast-card icon is #{ratio}:1 on #{tone}-surface, under the " \
          "#{non_text_floor}:1 non-text floor."
      end
    end
  end

  # The on-toast tokens hold a literal copy of the OTHER theme's signal text
  # value, because a var() cannot reach across theme blocks. That coupling is
  # invisible, so it is asserted rather than trusted to a comment.
  it "keeps each on-toast icon token equal to the opposite theme's signal text token" do
    { light: :dark, dark: :light }.each do |pill_theme, source_theme|
      %w[info success].each do |tone|
        expect(token(semantic, "#{tone}-icon-on-toast", pill_theme))
          .to eq(token(signals, tone, source_theme)),
            "--color-#{tone}-icon-on-toast in the #{pill_theme} block should mirror " \
            "--color-#{tone} from the #{source_theme} block — the pill inverts, so its " \
            "foreground comes from the other theme. Move them together."
      end
    end
  end

  # The config is what actually reaches the view; a correct token nobody
  # references fixes nothing.
  it "wires the pill tiers to the on-toast tokens and the card tiers to the text tokens" do
    types = Rails.application.config.toasts[:types]

    types.each do |name, config|
      if config[:tier] == :pill
        expect(config[:icon_color]).to match(/-icon-on-toast\z/),
          "#{name} is a pill, so its icon must use an -on-toast token, not #{config[:icon_color]}"
      else
        expect(config[:icon_color]).not_to match(/-icon\z/),
          "#{name} is a card on a tinted signal surface; #{config[:icon_color]} measured under " \
          "the non-text floor there. Use the tone's text token."
      end
    end
  end
end
