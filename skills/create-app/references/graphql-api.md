# GraphQL API (graphql-ruby)

Applies when Step 2's API style answer is GraphQL, on top of the API-only stack (`references/api-development.md` still applies for auth/CORS — this covers the GraphQL-specific layer).

## Setup

```ruby
# Gemfile
gem 'graphql'

group :development do
  gem 'graphiql-rails'
end
```

```
bundle exec rails generate graphql:install
```

This creates `app/graphql/<app_name>_schema.rb`, a base `Types::BaseObject`, and a `types/query_type.rb`. Mount GraphiQL in development only:

```ruby
# config/routes.rb
if Rails.env.development?
  mount GraphiQL::Rails::Engine, at: "/graphiql", graphql_path: "api/graphql"
end
post "/api/graphql", to: "graphql#execute"
```

This works fine even in a plain `--api` Rails app with no asset pipeline — `graphiql-rails` serves its own JS/CSS through its Rails engine (`/graphiql-rails/...` routes), not through the host app's Sprockets/Propshaft setup. Don't assume it needs the asset pipeline re-enabled; confirm by booting the server and hitting `/graphiql` directly if in doubt.

## Strip unused generator scaffolding

`graphql:install` scaffolds for the general case — a Relay `Node` interface (global object IDs) with connection-style (cursor) pagination wired into `BaseObject`, a `mutation` root, and `app/graphql/resolvers/`. Two separate decisions determine what's actually dead weight, and they don't imply each other — a plan with mutations can still have zero use for the Relay Node/connection half, and vice versa:

**Relay Node + connection-style pagination** — prunable whenever the plan has no global-object-ID lookup (`node(id:)`/`nodes(ids:)` fields) and no cursor-based (`first`/`after`) pagination, regardless of whether mutations exist:

- Delete `app/graphql/types/node_type.rb`, and drop the `id_from_object`/`object_from_id` Relay methods from the schema class.
- `Types::BaseObject`'s `edge_type_class(Types::BaseEdge)` / `connection_type_class(Types::BaseConnection)` calls only exist to support connection pagination — drop them and delete the now-unreferenced `base_edge.rb`, `base_connection.rb`. (Leave `field_class Types::BaseField` — see below, it's shared with mutations.)
- If the plan needs pagination but not Relay's cursor style, see "Pagination without Relay connections" below instead of leaving this scaffolding in place unused.

**Mutation scaffolding** (`mutation_type.rb`, `base_mutation.rb`, `resolvers/`) — prunable only when the plan is genuinely read-only, not even planned for a later phase. When mutations are planned, keep `base_mutation.rb` as-is: `GraphQL::Schema::RelayClassicMutation` (its default parent class) is the standard graphql-ruby mutation base independent of the Node interface — it doesn't require Node/connections to be present, and it does reference `Types::BaseField`/`Types::BaseArgument`/`Types::BaseInputObject`, so those three stay regardless of the Relay Node decision above. Delete `app/graphql/resolvers/` only if nothing uses `GraphQL::Schema::Resolver` (plain instance methods on the type, as in the query examples below, are enough for most apps).

**Custom scalars/unions/interfaces/enums** — delete `base_scalar.rb`/`base_union.rb`/`base_interface.rb`/`base_enum.rb` (and drop `resolve_type` from the schema class) if the schema defines none of these — independent of both decisions above.

After deleting anything, boot the app and force an eager-load pass (`Rails.application.eager_load!` via `bin/rails runner`, not just a dev-server boot) — that catches any dangling constant reference a lazily-autoloaded dev boot would miss.

## Types map to models, not to the wire format 1:1

One `GraphQL::Types` object per domain model, exposing only the fields consumers actually need — not every column:

```ruby
# app/graphql/types/post_type.rb
module Types
  class PostType < Types::BaseObject
    field :id, ID, null: false
    field :title, String, null: false
    field :body, String, null: false
    field :published, Boolean, null: false
    field :author, Types::UserType, null: false
    field :comment_count, Integer, null: false

    def comment_count
      object.comments.size
    end
  end
end
```

`comment_count` here is a computed field with no backing column — resolved from the association at query time. Prefer `object.comments.size` over `.count` when `comments` is already loaded (via the query-level `includes` below) to avoid an extra query per post.

## The schema type name is not the Ruby class name

graphql-ruby derives a type's GraphQL name from its class name automatically, and **strips a trailing `Type`** in the process: `Types::PostType` becomes `Post` in the schema, not `PostType`. This is easy to miss because plain field selections never need to name the type explicitly — it only bites once something references the type by name, most commonly a frontend fragment (`fragment F on PostType { ... }`) or a union/interface member list. The error ("No such type `PostType`, so it can't be a fragment condition") usually only surfaces once the frontend is actually wired up, well after the backend type was written and looked fine.

Don't assume the schema name matches the class name — confirm it once eager-loaded, e.g. `bin/rails runner "puts YourAppSchema.types.keys.sort"`, and use that confirmed name in any fragment, union, or interface reference.

## Queries — what's readable

```ruby
# app/graphql/types/query_type.rb
module Types
  class QueryType < Types::BaseObject
    field :posts, [Types::PostType], null: false do
      argument :published, Boolean, required: false
    end
    field :post, Types::PostType, null: true do
      argument :id, ID, required: true
    end

    def posts(published: nil)
      scope = Post.includes(:author, :comments)
      published.nil? ? scope : scope.where(published: published)
    end

    def post(id:)
      Post.find_by(id: id)
    end
  end
end
```

`includes(:author, :comments)` here matters more than in a REST controller — a naive GraphQL resolver that lets each `PostType` field lazily load its own association turns one query into an N+1 across every item in the list, and it's easy to miss because there's no view template making the N obvious. For anything beyond this scale, add the `graphql-batch` gem to batch-load associations across a single query's resolution instead of relying on eager `includes` alone.

## Pagination without Relay connections

If the plan calls for pagination but not the Relay Node/connection scaffolding (the common case for a small app — see "Strip unused generator scaffolding" above), plain offset/limit pagination behind a wrapper type is simpler than adopting `first`/`after` cursors. Return a plain type carrying the page plus metadata, resolved from a plain Ruby Hash — graphql-ruby's default field resolution supports Hash-keyed objects out of the box (falls back to `hash[field_method_name]` when the object doesn't respond to the field's method), so the wrapper type needs no backing model or explicit `hash_key:` on each field, as long as the Hash's keys match the fields' underscored Ruby names:

```ruby
# app/graphql/types/posts_page_type.rb
module Types
  class PostsPageType < Types::BaseObject
    field :nodes, [Types::PostType], null: false
    field :total_count, Integer, null: false
    field :page, Integer, null: false
    field :per_page, Integer, null: false
    field :total_pages, Integer, null: false
  end
end

# app/graphql/types/query_type.rb
field :posts, Types::PostsPageType, null: false do
  argument :page, Integer, required: false
  argument :per_page, Integer, required: false
end

def posts(page: 1, per_page: 10)
  scope = Post.includes(:author)
  page = [ page, 1 ].max
  per_page = per_page.clamp(1, 100)
  total_count = scope.count

  {
    nodes: scope.offset((page - 1) * per_page).limit(per_page),
    total_count: total_count,
    page: page,
    per_page: per_page,
    total_pages: (total_count.to_f / per_page).ceil,
  }
end
```

Clamp `per_page` and floor `page` at 1 rather than validating and raising — an out-of-range page should return an empty `nodes` array, not an error, since the client (e.g. clicking "Next" once too many times due to a race with a delete) shouldn't crash over it.

## Mutations — what's writable (skip this whole section for a read-only API)

One mutation class per write operation, not a single generic "update" mutation — this is what makes "what's mutable" explicit and lets each mutation define its own argument/error shape:

```ruby
# app/graphql/mutations/create_post.rb
module Mutations
  class CreatePost < BaseMutation
    argument :title, String, required: true
    argument :body, String, required: true

    field :post, Types::PostType, null: true
    field :errors, [String], null: false

    def resolve(title:, body:)
      post = context[:current_user].posts.build(title: title, body: body)
      if post.save
        { post: post, errors: [] }
      else
        { post: nil, errors: post.errors.full_messages }
      end
    end
  end
end

# app/graphql/types/mutation_type.rb
module Types
  class MutationType < Types::BaseObject
    field :create_post, mutation: Mutations::CreatePost
  end
end
```

`context[:current_user]` requires setting it in the controller (`context: { current_user: current_user }` when executing the schema) — see `references/api-development.md`'s devise-jwt section for where `current_user` comes from.

## Authorization

Field- or mutation-level, not just a blanket `before_action`. A common pattern is a `ready?`/`authorized?` check per mutation:

```ruby
class DestroyPost < BaseMutation
  argument :id, ID, required: true

  def resolve(id:)
    post = Post.find(id)
    raise GraphQL::ExecutionError, "Not authorized" unless post.author == context[:current_user]

    post.destroy
    { success: true }
  end
end
```

Don't rely on the frontend simply not showing a delete button — the mutation is reachable directly regardless of what the UI exposes.

## Errors

Prefer returning errors as part of the mutation's payload (the `errors: [String]` field above) over raising `GraphQL::ExecutionError` for validation failures — the former lets the client show field-level messages next to the form, the latter surfaces as a generic top-level GraphQL error. Reserve raised errors for authorization/not-found failures where there's no form to annotate.
