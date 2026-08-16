---
description: FDK — review a Rails project for correctness/simplification issues plus Rails-specific risk patterns. Invoked as /fdk:code-review [optional path or PR number].
---

Run two passes and merge the results into one report. Scope is "$ARGUMENTS" if given, otherwise the current diff.

## Pass 1 — General review

Invoke the `code-review` skill (medium effort unless the user asked for more) against the scope above. This covers correctness bugs and reuse/simplification/efficiency issues generically.

## Pass 2 — Rails-specific checklist

Independently check the same scope (the diff, or if there's no diff yet — e.g. a freshly scaffolded app with one commit — fall back to scanning `app/`, `config/routes.rb`, and `db/schema.rb`) against these Rails risk patterns a generic reviewer tends to miss:

- **Mass assignment** — controller actions that create/update records without `params.require(...).permit(...)`, or that use `permit!`.
- **Missing authorization** — controller actions lacking `before_action :authenticate_user!` (or equivalent) where the resource should require login; missing per-object authorization (any logged-in user can edit/delete records they don't own).
- **N+1 queries** — association access inside loops (views, serializers, controllers) without a corresponding `includes`/`eager_load`/`preload`.
- **Devise misconfiguration** — missing `config.action_mailer.default_url_options` for non-development environments; unconsidered defaults for `:trackable`/`:confirmable`/`:lockable` given the product's actual needs.
- **SQL injection** — raw string interpolation into `where`, `find_by_sql`, `order`, or `connection.execute` instead of parameterized/placeholder queries.
- **Missing indexes** — foreign key columns (`*_id`) or columns used in `where`/`order`/`joins` without a matching index in `db/schema.rb`.
- **Validation/schema mismatch** — model-level `validates presence: true` (or uniqueness) with no corresponding `NOT NULL` / unique index at the DB level.
- **Fat callbacks** — model callbacks doing slow or external work (API calls, emails, file processing) that should be a background job instead.
- **Leaked secrets** — credentials, API keys, or tokens hardcoded instead of using Rails credentials or ENV.
- **Broad CSRF/auth bypass** — `skip_before_action :verify_authenticity_token` or similar skips applied more broadly than necessary.

## Report

Combine both passes into one `ReportFindings` call, most-severe first, deduplicating anything both passes caught. Tag Rails-specific findings with category `rails-risk` so they're distinguishable from the general findings' categories.
