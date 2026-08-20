---
description: FDK — capture requirements for a new Rails product and scaffold it into ~/Documents/projects/<slug>. Invoked as /fdk:create-app <product description>.
version: 1.0.0
---

Turn the product description in "$ARGUMENTS" into a running Rails app skeleton in `~/Documents/projects/<slug>`, via requirements Q&A → approved plan → scaffold.

**Before starting each checkpoint in Step 4, re-read this file fresh from disk (even if it was already read earlier in the session) and print the version you loaded, e.g. `SKILL.md version: 1.0.0`.** This file gets edited between and during sessions — a copy cached in context from an earlier turn can silently miss rules that were fixed since, so treat "checkpoint start" as a trigger to reload it rather than trusting what's already in context.

Environment on this machine: Homebrew, mise-managed Ruby 3.3.12, Rails 8.1.3.1, Postgres 17 (running as a brew service). No Node.js installed — fine for the default importmap-based stack; flag it if the requirements need a JS build step (React, esbuild, etc.).

## Step 1 — Get the product description

Use "$ARGUMENTS" as the description. If it's empty, ask for a one-paragraph description of the product before continuing.

## Step 2 — Requirement-gathering Q&A

Ask conversationally, not as a single wall of questions. Cover:

- **Project slug** — short, dash-or-underscore name for the folder and Rails app.
- **Core domain entities** — the main "nouns" of the product (what models will exist).
- **Target users** — who uses this, and are there distinct roles (admin/customer/etc.)?
- **Auth** — does it need user accounts? Default assumption is yes → Devise. Skip only if the product genuinely has no login (e.g. an internal single-user tool). For any admin/internal role, also ask whether signup is self-service or console/seed-created only — default to console-only (no `:registerable`, `devise_for` scoped with `skip: [:registrations]`) unless the user explicitly wants open admin signup. Getting this wrong means anyone can self-register full admin access.
- **Stack** — always ask, no default: Hotwire/Turbo (server-rendered views, no separate frontend) vs. API-only Rails + a separate frontend app. Use `AskUserQuestion` since these are discrete, mutually exclusive options. See `references/hotwire-turbo.md` or `references/api-development.md` for what each choice implies (no Node.js on this machine affects the Hotwire default; Devise's session-cookie default affects API auth).
  - If API-only + separate frontend: also ask **API style** — REST JSON (`references/api-development.md`) vs. GraphQL (`references/graphql-api.md`) — and whether the frontend is a React SPA this skill should scaffold itself (Checkpoint D, via `scripts/scaffold_frontend.sh`) or an existing/separate frontend repo it shouldn't touch. Default to scaffolding it unless the user says the frontend already exists elsewhere.
- **Background jobs** — does anything need async processing (emails, imports, etc.)? If yes, note it for later (Solid Queue, Rails 8 default, needs no extra install — see `references/background-jobs.md`).
- **Fixed/exact-count fields** — if the spec describes a field as "exactly N" of something (N abilities, N photos, N variants...), and a real external data source is named (an API, a CSV, a scraped site), sanity-check the count against that source *before* locking it into the plan. A count that's aspirational rather than data-backed forces padding/placeholder workarounds throughout the seed script and every display layer downstream.
- **Public API + CSRF** — if the plan includes a JSON/GraphQL API mounted on a full (non-`--api`) Rails app, decide and note explicitly how CSRF protection is scoped for that endpoint: exempted entirely (fine for a genuinely read-only, no-mutations API), or left in place/scoped narrowly if mutations are planned even for a later phase. Don't leave this to implementation-time judgment — a broad exemption made "just to unblock fetch calls" silently covers every mutation added later too. See `references/api-development.md` for the scoped-exemption pattern.
- **Anything notable** — payments, file uploads, third-party integrations, anything that affects gem choices.

Baseline defaults (used unless the conversation says otherwise): RSpec for tests, Devise for auth, Postgres for the database.

## Step 3 — Write the plan and get approval

Summarize into a short spec: product name + one-line description, slug, entities, auth approach (including admin signup policy, if relevant), stack choice, API style and frontend-scaffolding decision (if applicable), key gems, initial models/routes, and the CSRF decision for any public API. Present it in chat and explicitly ask for a go-ahead.

**Do not scaffold anything until the user approves the plan.**

## Step 4 — Scaffold, in checkpoints

Once approved, build the app in checkpoints instead of generating everything in one pass. After each checkpoint below: **build** the work without committing it yet, **narrate** what got built and why (not just which commands ran), **show** one concrete artifact so the user can sanity-check it, then **stop and wait** for the user's go-ahead — treat this the same as Step 3's plan approval, not an optional pause. Only commit once the user approves; the commit is the last thing that happens before moving to the next checkpoint, never before the review. (Checkpoint A's plan-file commit is the one exception — it's made immediately, before any review, purely so the approved plan survives a crash or a dropped session; see that step for why.) Run only the checkpoints the chosen stack needs: a Hotwire-only app is just Checkpoints A and C; API-only + frontend runs all five (A through E). Tests get their own checkpoint right after the layer they cover, rather than one combined checkpoint at the end — Checkpoint C tests the backend immediately after Checkpoints A/B, before any React work starts, and Checkpoint E tests the frontend immediately after Checkpoint D. Writing each layer's tests while it's still fresh beats reconstructing the whole app's surface from memory in one big pass at the end.

**Live verification can hit a dev database the user is already using.** Checkpoints B/D's "Show" step means running the actual dev server and, often, creating records to demonstrate a query/mutation/page working. The user may already be running their own copy of that same server against the same dev database — checking, testing something, just poking at what's been built so far — and its rows are indistinguishable from scratch data once both exist. Before seeding anything for a demo, check whether the table already has rows (`Model.count`, or equivalent) rather than assuming it's empty; if it isn't, treat existing rows as the user's, not yours to touch. When seeding is genuinely needed, use a value no real record would plausibly have (a reserved fake domain in a URL column, a title prefix, etc.) so the rows can be identified and removed precisely afterward — never a bare `Model.destroy_all`/`delete_all` after a demo, since that can't tell your rows apart from ones that were already there.

### Checkpoint A — Data model & scaffolding

Generate the backend skeleton: models, migrations, associations, and the admin routes/controllers.

1. Run the scaffold script:
   ```
   ~/.claude/skills/fdk/scripts/scaffold.sh --name <slug> --stack <hotwire|api> --auth <devise|none> --test rspec --db postgresql
   ```
   This creates the Rails app in `~/Documents/projects/<slug>`, adds the baseline gems, creates the database, and makes the initial git commit. It fails loudly (non-zero exit, clear message) if the target folder already exists or if required tools are missing — read the error and fix the underlying issue rather than retrying blindly.
2. If Step 2's plan scaffolds a separate frontend (as opposed to an existing/external frontend repo), kick off `scripts/scaffold_frontend.sh` now, as a second background shell command (`run_in_background: true`), instead of waiting until Checkpoint D. It only needs `--name`/`--api-style`/`--api-url` — none of which depend on anything this checkpoint or Checkpoint B produce — so its slow part (`mise`/`npm install`) overlaps with backend work instead of adding wall-clock time later. Background it directly with a second shell call; don't spawn an agent to run it. The script is fully deterministic with no judgment calls to make, and a spawned agent's own startup reasoning adds real dispatch latency (measured ~15-20s in practice) on top of the script's own runtime, for no benefit over just backgrounding the command. Note in this checkpoint's narration that the frontend scaffold is running in the background, so the user isn't surprised by its git-init/commit activity later. Checkpoint D then checks on this job rather than re-running it — see its step 1.
3. Open the project in the user's editor as soon as it exists, so they can follow along in their own window as the rest of the checkpoints build on it.
   - If Step 2's plan scaffolds a separate frontend (step 2 above just kicked it off in the background), open the combined workspace now rather than the Rails folder alone — write `~/Documents/projects/<slug>.code-workspace` with two folder roots (`~/Documents/projects/<slug>` and `~/Documents/projects/<slug>-frontend`), then `open -a "Visual Studio Code" ~/Documents/projects/<slug>.code-workspace`. The frontend folder won't exist yet at this exact moment (its scaffold is still running in the background) — that's fine, VS Code shows it once the folder appears a few seconds later, and the user never has to deal with a single-project window that gets swapped out mid-build later. Note this in the narration so the brief "missing folder" state isn't a surprise.
   - Otherwise (Hotwire-only, or an external frontend this skill isn't touching), just open the Rails folder: `open -a "Visual Studio Code" ~/Documents/projects/<slug>`.
   - Either way, use `open -a`, not the `code` CLI (`code` isn't guaranteed to be on `PATH` even when VS Code is installed). If the `open -a` call fails (VS Code not installed), don't block on it — note it to the user and continue.
4. Immediately after the scaffold succeeds — before generating anything else — write the full approved plan from Step 3 verbatim into `.claude/PLAN.md` in the new project, and commit it on its own (`git add .claude/PLAN.md && git commit -m "Add approved plan"`). This is the persistence step: the rest of Step 4 can get interrupted (crash, closed session, a new session later opened directly on this project directory with no memory of the planning conversation), and the plan must already be on disk so work can resume from it instead of being lost. Include, at minimum: the product description, slug, entities, auth approach, stack choice, API style/frontend decision, key gems, and the ordered build steps you're about to execute.
5. `cd` into the new project and generate:
   - Auth, if enabled: `rails generate devise User` (add any extra fields the requirements called for), then `rails db:migrate`. For an admin/internal role scoped under its own routes (e.g. `namespace :admin`), route `devise_for` under that same path instead of Devise's pluralized default — e.g. `devise_for :admins, path: "admin", path_names: { sign_in: "login", sign_out: "logout" }` — so auth and the panel it guards live under one consistent prefix (`/admin/login`, not `/admins/sign_in` next to `/admin/pokemons`). Apply the console-only signup decision from Step 2 here too (`skip: [:registrations]` and no `:registerable` module, unless open signup was explicitly requested).
     - **Naming gotcha:** `devise_for :admins` generates a model class literally named `Admin`. That collides with `namespace :admin`'s controllers, which Rails/Zeitwerk expect to live under a `module Admin` — but `module Admin ... end` raises `TypeError: Admin is not a module` once `Admin` already refers to a class. Prefer naming the model `AdminUser` instead (`rails generate devise AdminUser`, `devise_for :admin_users, path: "admin", ...`) to avoid the collision entirely. If `Admin` is kept anyway, write every controller under that namespace with compact class syntax — `class Admin::PokemonsController < Admin::BaseController` — never the `module Admin ... end` block form.
   - Models/migrations for the core entities identified in Step 2, only what the plan actually calls for. Follow `references/active-record.md` for migration/validation/index conventions (matching DB constraints to model validations, indexing foreign keys and filter columns, `belongs_to` defaults).
   - Admin routes/controllers/views as plain server-rendered Rails (Hotwire) views — even when the overall stack is API + React. An admin panel is internal tooling; wiring the same CRUD through the GraphQL/REST layer and the React app just to manage it costs more than it buys. Only build admin UI in React too if the plan explicitly calls for it (e.g. the admin needs the same rich interactivity as the main product). Invoke the `ui-styling` skill before writing these views' markup/styling.
6. **Remove unnecessary scaffolding.** `rails new` and its generators produce boilerplate for features most apps don't end up using — clean this up now, before the first commit, rather than letting it accumulate across checkpoints. Two tiers, handled differently:
   - **Dead generator output — remove without asking.** Files/code with zero functional value that nothing references: empty `app/{controllers,models}/concerns/.keep` placeholder dirs; `app/javascript/controllers/hello_controller.js` (Stimulus's demo controller — grep views for `data-controller="hello"` first, but it's essentially always unused); `app/views/pwa/*` when the PWA routes in `config/routes.rb` are left commented out (Rails' own default); and empty controller action stubs like `def edit; end` — Rails' `ActionController::ImplicitRender` renders the matching template with no method defined at all as long as a `before_action` already set the needed instance variables, so verify this live (hit the route with the method removed, confirm it still 200s) rather than asserting it from memory, then delete the stub. Run `Rails.application.eager_load!` via `bin/rails runner` and re-run any specs after removals to catch dangling references.
   - **Unused platform subsystems — ask first.** Action Mailer (`app/mailers/`, mailer layouts, per-environment mailer config), Active Job's `ApplicationJob`, Solid Queue/Cache/Cable (gems, `config/{cache,queue,cable,recurring}.yml`, `db/*_schema.rb`, `bin/jobs`, the adapter lines in `config/environments/production.rb` and the extra databases in `config/database.yml`), Kamal/Docker (`config/deploy.yml`, `.kamal/`, `Dockerfile`, `.dockerignore`, deploy binstubs), and the CI workflow (`.github/workflows/ci.yml`, `.github/dependabot.yml`) are real Rails 8 defaults, not dead code — removing them is an architecture call (no background jobs, no deploy path, no CI) that may not match what the user wants later. Use `AskUserQuestion` to confirm the scope before touching any of these; a plan with background jobs or a deploy target already identified in Step 2 means leaving the corresponding piece in place. After removal: update the Gemfile, run `bundle install` to prune `Gemfile.lock`, and re-verify boot + eager load + test suite — a stale adapter reference (e.g. `config.cache_store = :solid_cache_store` after removing the gem) fails at runtime, not at edit time.

Narrate how the spec became a data model (which nouns became tables, which became associations vs. columns), what fields/associations were chosen and why, if applicable why the admin got plain Rails views instead of React, and what generator scaffolding got stripped and why (naming the dead files, and separately naming anything held back pending the user's answer on platform subsystems).

Show: open one migration and one model file, and point at anything non-obvious (a validation, an association, an index) rather than reading the whole thing back.

Then stop and wait for the go-ahead before committing. Once approved, commit: `git add -A && git commit -m "Add data model and admin scaffolding"` — then move to the next checkpoint (Checkpoint B, or Checkpoint C directly if the stack is Hotwire-only).

### Checkpoint B — API layer (skip if the stack is Hotwire-only)

Add the GraphQL or REST layer identified in Step 2, and finish the admin CRUD views here if Checkpoint A didn't already cover them.

1. GraphQL: follow `references/graphql-api.md` — types per model, a query type, mutations per write operation, GraphiQL mounted in development.
   REST: follow `references/api-development.md` — versioned controllers, serialization, centralized error handling.

Narrate how types/endpoints map to the models from Checkpoint A, what's queryable vs. mutable, and any computed/resolved fields (e.g. a `comment_count` with no backing column).

Show: run one query live in GraphiQL (or hit one endpoint with `curl` for REST), and click through the admin CRUD in the browser. For GraphQL, also open the GraphiQL URL (`http://localhost:3000/graphiql` by default — adjust for whatever port the dev server actually bound to) in a browser tab via the `claude-in-chrome` tools, so the user has it ready to poke at themselves instead of just seeing a description of it. Pre-fill the editor with a real, runnable example instead of leaving it blank — GraphiQL reads an initial query (and `variables`/`operationName`) from URL-encoded `?query=`/`?variables=` params, so navigate straight to a URL carrying one; if the mounted version doesn't pick those up, type the query into the editor directly via `computer` instead. Cover a query and, if any mutations exist, one mutation too — pick ones that touch real seeded/example data (real ids, not placeholders) so running them on the spot actually returns something. Narrate two or three more variations (a filtered query, another mutation) directly in chat as copy-pasteable GraphQL, the same way the final report hands over `curl` examples, so the user has several working starting points instead of just the one query left in the editor.

Checkpoint line before moving on: "Backend's done and queryable — let's lock it in with tests before moving on to React."

Then stop and wait for the go-ahead before committing. Once approved, commit: `git add -A && git commit -m "Add <GraphQL|REST> API layer"` — then move to Checkpoint C.

### Checkpoint C — Backend tests

Add automated test coverage for the backend built so far (Checkpoint A's data model and admin views, plus Checkpoint B's API layer if the stack has one). This runs immediately after Checkpoint A (Hotwire-only apps) or Checkpoint B (API + frontend apps) — always *before* any React work starts, so the backend is locked in and verified while it's still fresh rather than reconstructed from memory alongside the frontend tests later. Skip only if the user explicitly says they don't want tests yet; the baseline default (Step 2) is RSpec.

Follow `references/rspec-testing.md`. At minimum: model specs covering validations *and* any custom business logic (computed methods — not just column presence), and request specs for the admin CRUD and, if Checkpoint B ran, the API layer (GraphQL or REST) — including the unauthenticated-redirect case for admin and at least one query/mutation or endpoint per resource.

- For a small app (a handful of models, little association complexity), plain `Model.create!`/`Model.new` calls in specs are a reasonable substitute for `rspec-testing.md`'s FactoryBot/Faker default — reach for factories once hand-written instantiation starts repeating across many specs, not preemptively.

Run the full suite (`bundle exec rspec`) and fix failures before moving on — don't report this checkpoint done with red tests.

Narrate what's covered and, as importantly, what's deliberately not (e.g. system specs, unless the plan called for a flow that crosses multiple pages).

Show: the test run output (pass count), not just that files were created.

Then stop and wait for the go-ahead before committing. Once approved, commit: `git add -A && git commit -m "Add backend test coverage"` — then move to Checkpoint D if the stack scaffolds a React frontend, or continue to Step 5 (Report) if Hotwire-only.

### Checkpoint D — React SPA (skip unless Step 2 chose to scaffold the frontend)

Generate the SPA that consumes the API layer from Checkpoint B. Follow
`references/react-typescript.md` throughout this checkpoint — it covers the Apollo
Client version-drift gotcha, why `@types/react` may mark a familiar type
`@deprecated` (don't reach for a React API from memory without checking), stripping the
Vite template's unused marketing-page boilerplate, and multi-project dev-server/port
hygiene on this machine. Also invoke the `react-best-practices` and `ui-styling` skills
before writing any component code, and apply their guidance for the rest of the checkpoint.

1. Check on the frontend scaffold. If Checkpoint A kicked it off in the background, wait for that job's completion notification rather than re-running it — read its output to confirm it succeeded (git commit made, `.env` written). If it failed, or it was never started (frontend already exists elsewhere, or an earlier session skipped it), run it now, synchronously:
   ```
   ~/.claude/skills/fdk/scripts/scaffold_frontend.sh --name <slug>-frontend --api-style <graphql|rest> --api-url <api-url>
   ```
   This creates a Vite + React (TypeScript) app in `~/Documents/projects/<slug>-frontend`, installs Apollo Client if the API style is GraphQL, writes the API URL into `.env`, and makes the initial git commit. It installs Node via `mise` first if Node isn't already available.
   - Checkpoint A's step 3 already opened the combined `.code-workspace` (both folder roots) as soon as the background scaffold was kicked off, so there's normally nothing further to do here editor-wise. The one exception: if this step just ran `scaffold_frontend.sh` synchronously because Checkpoint A's background job never started (e.g. resuming a session interrupted before that point) or failed, write and open the combined workspace now the same way Checkpoint A's step 3 would have.
2. Wire up data fetching against the running API: an Apollo Client instance pointed at `VITE_API_URL` for GraphQL, or a small typed fetch wrapper for REST. See `references/react-typescript.md` for the current Apollo Client import shape — it moves across majors and `scaffold_frontend.sh` always installs `latest`.
3. Build one page that proves connectivity — typically a list view of the plan's primary entity — rather than scaffolding every screen up front.

Narrate how the SPA's data fetching maps to the API layer from Checkpoint B, and what's client-side state vs. server state.

Show: run the Vite dev server, load the page in a browser, and point out the data round-tripping from Postgres through the API into the UI.

Then stop and wait for the go-ahead before committing. Once approved, commit: `git add -A && git commit -m "Add initial page wired to the API"` — then move to Checkpoint E.

### Checkpoint E — Frontend tests (skip unless Checkpoint D ran)

Add automated test coverage for the React SPA built in Checkpoint D. This runs immediately after it, as the last checkpoint. Skip only if the user explicitly says they don't want tests yet; the baseline default (Step 2) is a matching frontend test setup alongside the backend's RSpec suite.

Add Vitest + `@testing-library/react` (`npm install --save-dev vitest jsdom @testing-library/react @testing-library/jest-dom @testing-library/user-event`), a `test` script in `package.json`, and a `test` block in `vite.config.ts` (`environment: 'jsdom'`, a setup file importing `@testing-library/jest-dom/vitest`).

- **Register `afterEach(cleanup)` explicitly in the setup file.** Testing Library's auto-cleanup between tests depends on a global `afterEach`, which only exists if `test.globals: true` is set in the Vitest config. Without either, DOM from one test leaks into the next and produces confusing "multiple elements found" failures that look unrelated to the real cause.
- For GraphQL, mock the API with `MockedProvider` rather than hitting the real backend (see the Apollo Client version note in `references/react-typescript.md` for where it actually lives in the installed version).
- **Every object in a mocked result needs `__typename`, matching the real schema type name** (see `references/graphql-api.md`'s note on type names not matching the Ruby class name). Without it, `InMemoryCache` silently normalizes the object away to `{}` — no warning, no error, just fields quietly missing several components downstream, which is a confusing thing to debug blind. Add `__typename` to every nested object in every mock, not just the top-level one.

Run the full suite (`npm test`) and fix failures before moving on — don't report this checkpoint done with red tests.

Narrate what's covered and, as importantly, what's deliberately not (e.g. E2E specs, unless the plan called for a flow that crosses multiple pages).

Show: the test run output (pass count), not just that files were created.

Then stop and wait for the go-ahead before committing. Once approved, commit: `git add -A && git commit -m "Add frontend test coverage"` — then continue to Step 5 (Report).

## Step 5 — Report

After whichever checkpoints ran, tell the user: the project path(s) (Rails app, plus the frontend app if scaffolded, plus the `.code-workspace` file if the plan scaffolded a frontend), how to run each (`bin/dev` for Hotwire, `bin/rails server` for API-only, `npm run dev` for the frontend), how to run the tests (`bundle exec rspec`, `npm test`), and a short list of suggested next steps (e.g. "add the Post model's remaining fields", "wire up the dashboard view", "add the next GraphQL mutation").

If Checkpoint B ran (the app has an API layer), also include a block of ready-to-run `curl` examples — this is what the user tests the API with directly and demos to their team, so it needs to be handed over here, not left implicit. Cover a full cycle for the primary resource(s), not just a health check: list, create, the filter/query variants the plan called for, and delete/update if the API exposes them. For REST, one `curl` per endpoint with a realistic example payload; for GraphQL, one `curl -X POST` per query/mutation with the query/variables in the JSON body, pointed at the GraphQL endpoint. Use the app's actual running URL (`http://localhost:3000` by default) and real ids from the seeded/example data where an endpoint needs one, noting that ids will need swapping for whatever the user's data actually has by then. These are handed to the user to run themselves — don't execute them as part of this step.
