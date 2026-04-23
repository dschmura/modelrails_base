# Deployment

This app deploys with **Kamal** (Rails 8 default). Most configuration follows standard Kamal + Rails docs; this page documents project-specific gotchas that aren't obvious from the Rails scaffold.

## SSL configuration: paired changes required

When you enable TLS termination via the Kamal proxy, you **must also** enable the matching settings in `config/environments/production.rb`. These are a package deal — enabling one without the other silently breaks sessions or causes redirect loops.

### The three Rails settings

Uncomment all three in `config/environments/production.rb`:

```ruby
# Trust the SSL-terminating proxy's X-Forwarded-Proto header.
# Without this, Rails sees only the plain HTTP from kamal-proxy
# inside the container, so cookies won't get the Secure flag.
config.assume_ssl = true

# Redirect HTTP → HTTPS, enable Strict-Transport-Security header,
# mark cookies Secure. Requires assume_ssl so the redirect logic
# can detect requests that are already HTTPS via the proxy.
config.force_ssl = true

# Exclude the Kamal health check endpoint from the HTTPS redirect.
# kamal-proxy hits /up over HTTP inside the container — without
# this, health checks 301-redirect and fail, causing Kamal to
# mark the app unhealthy and refuse to roll forward.
config.ssl_options = { redirect: { exclude: ->(request) { request.path == "/up" } } }
```

### Kamal proxy setting

At the same time, uncomment in `config/deploy.yml`:

```yaml
proxy:
  ssl: true
  host: yourdomain.com
```

### Why they can't be enabled independently

Valid combinations:

- ✅ All enabled together (proxy + `assume_ssl` + `force_ssl`) → correct production behavior
- ✅ All disabled together → correct for local dev/test (no SSL)

Broken combinations:

- ❌ `assume_ssl` on, no proxy → sessions break (cookies get `Secure` flag but travel over HTTP)
- ❌ `force_ssl` on, no proxy → redirect loop (app redirects to HTTPS, proxy passes requests back as HTTP)
- ❌ `force_ssl` on, `assume_ssl` off, proxy on → redirect loop (app can't detect proxy's HTTPS signal, redirects every request)

### Deployment checklist

When preparing the first SSL-enabled deploy, change these in the **same commit**:

- [ ] Uncomment `proxy:` block in `config/deploy.yml` with your real domain
- [ ] Uncomment `config.assume_ssl = true` in `config/environments/production.rb`
- [ ] Uncomment `config.force_ssl = true` in `config/environments/production.rb`
- [ ] Uncomment `config.ssl_options = { ... }` in `config/environments/production.rb`
- [ ] Update `config.action_mailer.default_url_options[:host]` to your real domain
- [ ] Update `config.hosts` if enabling DNS rebinding protection

Test locally with `RAILS_ENV=production bin/rails server` to catch any redirect loops before deploying.

## Development environment notes

### CSP exception for letter_opener_web

The production CSP defined in `config/initializers/content_security_policy.rb` sets `frame_src :none` and a nonce-enforced `script_src`. Those rules block the `letter_opener_web` email-preview iframe and its inline scripts.

Because the engine is mounted only when `Rails.env.development?` (see `config/routes.rb`), CSP is disabled for the gem's controllers in a dev-only initializer at `config/initializers/letter_opener_web.rb`:

```ruby
Rails.application.config.to_prepare do
  next unless Rails.env.development?
  next unless defined?(LetterOpenerWeb::ApplicationController)

  LetterOpenerWeb::ApplicationController.content_security_policy false
end
```

This doesn't relax CSP anywhere else — the main app's CSP stays intact in every environment. The `X-Frame-Options: SAMEORIGIN` header from `config/initializers/security_headers.rb` is also preserved, so cross-origin iframing is still blocked.

No production impact: the engine isn't mounted, so the initializer's guards short-circuit before touching the constant.
