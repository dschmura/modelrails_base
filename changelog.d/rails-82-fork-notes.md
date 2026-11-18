### Breaking

- **Rails 8.2's defaults, shipped in v2026.10.27 without this note.** The app takes every 8.2 default (#1342), and the test environment shuffles unordered queries (#1343). What a fork's own code can hit:
  | Failure in your fork | Remedy |
  |---|---|
  | `ActionView::SyntaxErrorInTemplate` from one of your views that rendered before, naming an unclosed tag or ERB output where an attribute name goes | HTML templates compile through Herb, which parses the markup. `bin/rails herb:check` lists every template it rejects; fix the markup it names |
  | A POST from a script, a webhook sender or a browser without `Sec-Fetch-Site` gets 422, though it carries a valid authenticity token | Writes are verified by `Sec-Fetch-Site` alone (`:header_only`), and forms no longer render a token. Give a non-browser caller its own controller, with `skip_forgery_protection` and its own authentication; to accept tokens again, set `config.action_controller.forgery_protection_verification_strategy = :header_or_legacy_token`. /docs/developer/security (Cross-Site Request Forgery) |
  | A job enqueued inside a transaction isn't there until the transaction commits, and never is if it rolls back | Jobs enqueue after the commit. For a job that must enqueue at once, set `self.enqueue_after_transaction_commit = false` in it |
  | A spec of yours fails on every run where it used to pass most runs, comparing records in an order no query asks for | `config/environments/test.rb` shuffles every unordered SELECT. Add the `order` the code means, or compare with `match_array`. /docs/developer/testing (Unordered queries come back shuffled) |

### Fixed

- v2026.10.27's notes were wrong in three places: the app runs `load_defaults 8.2`, not 8.1; Bullet loads without a patch; and Lexxy's ALT button is on. Images saved under Lexxy 0.9 need `bin/rails action_text:clear_filename_alts` once (/docs/developer/getting-started).
- The testing guide explains why unordered queries come back shuffled in specs, and Getting Started gives the Kamal form of `action_text:clear_filename_alts`.
