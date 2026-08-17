# React + TypeScript frontend (Vite)

Applies when Checkpoint D scaffolds a React SPA via `scripts/scaffold_frontend.sh`, on top
of `references/api-development.md` (REST) or `references/graphql-api.md` (GraphQL) for how
the API layer itself works.

## Don't assume a React API is still current — check the installed types

Training data reflects React/TypeScript conventions that may already be marked
`@deprecated` in the version actually installed. `@types/react` ships JSDoc `@deprecated`
annotations directly in its `.d.ts` files, and those are the authority — not habit or
what looked right in an older project. Before reaching for a React type from memory
(event types are the most common trap), check whether it's still current:

```
grep -n "@deprecated" node_modules/@types/react/index.d.ts
```

Concretely: recent `@types/react` marks `FormEvent` deprecated —

```ts
/**
 * @deprecated FormEvent doesn't actually exist.
 *             You probably meant to use {@link ChangeEvent}, {@link InputEvent}, {@link SubmitEvent}, or just {@link SyntheticEvent} instead
 *             depending on the event type.
 */
interface FormEvent<T = Element> extends SyntheticEvent<T> {}
```

— so a form's `onSubmit` handler should type its event as `SubmitEvent`, not `FormEvent`:

```tsx
async function handleCreate(e: SubmitEvent) {
  e.preventDefault();
  // ...
}

<form onSubmit={handleCreate}>
```

This applies generally, not just to this one type. TypeScript happily compiles code that
uses a deprecated type — deprecation is an IDE/editor hint surfaced via JSDoc, not a
compiler error — so a clean `npx tsc -b` is not confirmation an API is current. Grep for
`@deprecated` near anything pulled from React's type exports on autopilot, and prefer
whatever the installed `.d.ts` actually recommends over a remembered pattern.

## Apollo Client's API shape moves across majors — re-verify per project

`scaffold_frontend.sh` installs whatever `latest` resolves to at scaffold time, so don't
assume the mapping below still holds for a new project — confirm it:

```
cat node_modules/@apollo/client/package.json | python3 -c "import json,sys; print(json.load(sys.stdin)['exports'])"
```

As of Apollo Client v4:
- `ApolloClient`, `HttpLink`, `InMemoryCache`, `gql` — import from `@apollo/client` (root,
  which maps to `./core/index.js`).
- `ApolloProvider`, `useQuery`, `useMutation` — moved to the `@apollo/client/react`
  subpath.
- `MockedProvider` (for tests, see `references/rspec-testing.md`'s frontend section in
  SKILL.md) — moved to `@apollo/client/testing/react`. The `MockedResponse` *type* did
  not move with it — that subpath only exports `MockedProvider`/`MockedProviderProps`.
  `MockedResponse` now lives as `MockLink.MockedResponse` under the non-`/react` path,
  `@apollo/client/testing`:
  ```ts
  import { MockedProvider } from "@apollo/client/testing/react";
  import type { MockLink } from "@apollo/client/testing";

  const mock: MockLink.MockedResponse = {
    request: { query: GET_BOOKMARKS, variables: {} },
    result: { data: { bookmarks: [] } },
  };
  ```
  Importing `MockedResponse` from `@apollo/client/testing/react` fails immediately with
  "has no exported member 'MockedResponse'" — easy to reach for anyway since
  `MockedProvider` (which *does* live there) is naturally imported on the same line out
  of habit.
- The `uri` shorthand on the `ApolloClient` constructor is gone — construct an explicit
  `HttpLink` instead.

```ts
// src/apollo-client.ts
import { ApolloClient, HttpLink, InMemoryCache } from "@apollo/client";

export const apolloClient = new ApolloClient({
  link: new HttpLink({ uri: import.meta.env.VITE_API_URL }),
  cache: new InMemoryCache(),
});
```

```tsx
// src/main.tsx
import { ApolloProvider } from "@apollo/client/react";
```

Also deprecated as of v4, same `@deprecated`-JSDoc mechanism as the React event-type note
above — passing a generic directly to `useQuery`/`useMutation` (`useQuery<BookmarksData>(GET_BOOKMARKS, ...)`):

```
grep -n "@deprecated" node_modules/@apollo/client/react/hooks/useQuery.d.ts node_modules/@apollo/client/react/hooks/useMutation.d.ts
```

The replacement is to type the query/mutation document itself as `TypedDocumentNode<TData,
TVariables>` (exported from `@apollo/client`) instead of a plain return from `gql`, and let
`useQuery`/`useMutation` infer both type parameters from it — no generic at the call site:

```ts
// src/graphql.ts
import { gql, type TypedDocumentNode } from "@apollo/client";

interface BookmarksData { bookmarks: BookmarksPage }
interface BookmarksVariables { search?: string; tag?: string }

export const GET_BOOKMARKS: TypedDocumentNode<BookmarksData, BookmarksVariables> = gql`
  query GetBookmarks($search: String, $tag: String) { ... }
`;
```

```tsx
// no generic needed — TData/TVariables both come from the document's type
const { data } = useQuery(GET_BOOKMARKS, { variables: { search } });
```

This also fixes mock type-checking in tests for free: `MockedProvider`'s mocks match
against the same `TypedDocumentNode`, so a mock's `variables`/`result.data` shape is
checked against the real query/mutation types instead of being an untyped `any`.

## `import.meta.env` typechecks out of the box — don't hand-roll env typing

Vite's scaffolded `tsconfig.app.json` already sets `"types": ["vite/client"]`, which
provides `ImportMetaEnv`/`ImportMeta` typing. `import.meta.env.VITE_API_URL` typechecks
without a manual `src/vite-env.d.ts` — don't add one preemptively; it's dead weight if
nothing needs stricter typing than what `vite/client` already provides.

## Strip the Vite template's marketing-page boilerplate

`npm create vite@latest --template react-ts` scaffolds a marketing landing page, not a
blank app: a hero image, framework logos, a `#root { width: 1126px; ...; border-inline }`
fixed-width centered layout, 56px hero-sized headings, and several unused CSS custom
properties (`--shadow`, `--social-bg`, etc.). None of it belongs in a real app, and left
in place it visibly clashes with real content — oversized headings, unwanted side
borders framing the page. Before building the actual UI:

- Delete `src/assets/react.svg`, `src/assets/vite.svg`, `src/assets/hero.png`,
  `public/icons.svg` (or whichever the real app doesn't reference).
- Rewrite `src/index.css`: keep the light/dark CSS-variable split (genuinely useful — see
  below) but drop the fixed-width `#root` rule, the hero-sized `h1`/`h2`, and any custom
  property nothing references anymore.
- Rewrite `src/App.css` and `src/App.tsx` wholesale rather than editing around the
  template's demo markup — the counter button and "Edit src/App.tsx and save" copy have
  nothing to do with the app being built.
- Update `index.html`'s `<title>` away from the scaffold's default (the
  `<slug>-frontend` package name).

## Keep the light/dark theme tokens, and actually use them in new component CSS

The template's `:root` / `@media (prefers-color-scheme: dark)` variable split is worth
preserving — it's what makes the app respect the OS theme instead of looking broken in
one mode. When writing component CSS, reference the tokens (`var(--border)`,
`var(--text)`, etc.) rather than hardcoding colors picked while looking at only one
theme — a light-gray border that reads fine in dark mode can be nearly invisible (or the
wrong contrast) in light mode, and vice versa.

## Running the dev server alongside other projects on the same machine

Multiple FDK-scaffolded projects on one dev machine compete for the same default ports —
Rails on 3000, Vite on 5173. This causes a few distinct failure modes worth knowing
about:

- **Vite auto-increments silently on a port collision.** If 5173 is taken, Vite just
  picks 5174 (or the next free port) and prints the actual port it bound to — read the
  printed `Local:` URL rather than assuming 5173, especially when something else on the
  machine might already be listening there.
- **A daemonized Rails server can look like it booted even when the port was taken.**
  `bin/rails server -d`'s startup banner prints before the daemonized child process
  confirms its bind succeeded, so a port collision can silently look like a clean boot —
  a request that "works" may actually be hitting an unrelated leftover server on that
  port. Confirm with `lsof -i :<port> -sTCP:LISTEN` and check which process actually owns
  it before trusting the banner or a single successful-looking request.
- **Keep CORS in sync with whichever port Vite actually landed on.** If Vite fell back to
  5174, the Rails CORS initializer's allowed origin (e.g. `FRONTEND_ORIGIN`) needs to
  match, or requests fail with a CORS error that looks unrelated to the real cause (a
  port mismatch).
- **Stop a dev server by the PID that owns the port, not by matching the process name.**
  `pkill -f vite` (or `-f "rails server"`) matches every process with that string
  anywhere in its command line — including unrelated dev servers left running from other
  projects on the same machine. Use `lsof -ti :<port> | xargs kill` to target only the
  process actually bound to the port just started.