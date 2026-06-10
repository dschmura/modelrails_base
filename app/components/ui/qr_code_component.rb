# frozen_string_literal: true

module UI
  # # QrCode
  #
  # A container that renders a QR code — either a pre-rendered image (`src:`) or raw
  # SVG/HTML from a generator gem such as `rqrcode` (block).
  #
  # ## Use when
  # - You need to display a scannable QR code and you already have the image URL or
  #   the gem-generated SVG markup.
  #
  # ## Don't use when
  # - You want a decorative graphic — a QR code is meaningful content (it encodes a
  #   payload), so it always carries an accessible name; use `image`/`figure` for
  #   ordinary imagery.
  #
  # ## Accessibility contract
  # - **Guarantees:** the wrapper is a single labelled graphic (`role="img"` +
  #   `aria-label`), so BOTH the `src:` and the block (raw-SVG) paths announce a real
  #   name to assistive tech — not a silent, unlabelled `<svg>` (WCAG 1.1.1 / 4.1.2).
  #   The inner `<img>` is marked decorative (`alt=""`) because the wrapper already
  #   carries the name, avoiding a double announcement. Caller `html_attrs` merge
  #   first; the `role`/`aria-label` apply as overrides so a caller can't strip the
  #   accessible name (mirrors `chart`/`rating`).
  # - **You supply:** a meaningful `alt:` that describes what the code encodes
  #   (e.g. "QR code linking to example.com"), not a bare "QR code".
  #
  # ## Parameters
  # - `src:` pre-rendered image URL; renders an `<img>` when provided (optional)
  # - `alt:` accessible name for the code — describe what it encodes (default: "QR code")
  # - `size:` pixel dimensions of the `<img>` (ignored for block content; default: 200)
  # - `**html_attrs:` forwarded to the wrapper `<div>`
  #
  # ## Usage (in an ERB view)
  #   ui :qr_code, src: qr_url, alt: "QR code linking to example.com"
  #
  #   ui :qr_code, alt: "QR code linking to example.com" do
  #     RQRCode::QRCode.new("https://example.com").as_svg(viewbox: true).html_safe
  #   end
  class QrCodeComponent < ApplicationComponent
    # bg-surface (a semantic token, not raw `bg-white`) + p-3 quiet zone keeps the
    # code on a light, high-contrast field that scanners need, in both themes.
    WRAPPER_CLS = "inline-flex items-center justify-center overflow-hidden rounded-lg bg-surface p-3"

    def initialize(src: nil, alt: nil, size: 200, **html_attrs)
      @src = src
      @alt = alt.presence || I18n.t("modelrails_ui.qr_code.label", default: "QR code")
      @size = size
      @extra_class = html_attrs.delete(:class)
      @html_attrs = html_attrs
    end

    def call
      content_tag(:div, **wrapper_attrs) do
        if @src
          # The wrapper carries the accessible name; the <img> is decorative so AT
          # announces the code once, not twice.
          tag.img(src: @src, alt: "", width: @size, height: @size,
            class: "block", loading: "lazy")
        else
          content
        end
      end
    end

    private

    # Caller html_attrs merge FIRST; role/aria-label apply as overrides so a caller
    # can't strip the accessible name off the labelled graphic.
    def wrapper_attrs
      attrs = {}
      @html_attrs.each { |k, v| attrs[k.to_s] = v }
      attrs["class"] = cn(WRAPPER_CLS, @extra_class)
      attrs["role"] = "img"
      attrs["aria-label"] = @alt
      attrs
    end
  end
end
