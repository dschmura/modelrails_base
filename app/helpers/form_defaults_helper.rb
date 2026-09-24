# Every form_with in the app renders `novalidate` unless it opts out (#1117).
#
# UI::FormBuilder's contract is one server-rendered validation path: it never
# emits native `required`, so the error summary and inline errors it exists to
# render are what a user meets. Input TYPES broke that quietly -- `type="email"`
# (and url, number, date) are validated by the browser, so a malformed value
# was blocked by a transient native bubble and never reached the server.
#
# The types stay: they pick the right mobile keyboard and drive autofill.
# `novalidate` suppresses only the browser's validation UI, so both survive and
# every rule routes through the server as the builder promises.
#
# Here rather than in the builder because the builder owns fields, not the
# <form> tag; and here rather than at 50 call sites so a fork's new form
# inherits it. Opt out with `html: { novalidate: false }` -- the caller's html
# options merge last. spec/code_smells/forms_route_through_form_with_spec.rb
# keeps every form on this path.
module FormDefaultsHelper
  def form_with(**options, &block)
    options[:html] = { novalidate: true }.merge(options[:html] || {})
    super
  end
end
