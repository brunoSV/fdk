# Active Record conventions

Applies when generating models/migrations in Step 4 of create-app.

## Match validations to DB constraints

Every `validates presence: true` needs a matching `null: false` on the column. Every `validates uniqueness: true` needs a matching unique index. Model-level-only validation is a race condition under concurrent requests — two requests can both pass the Ruby check before either commits.

```ruby
# migration
add_column :users, :email, :string, null: false
add_index :users, :email, unique: true

# model
validates :email, presence: true, uniqueness: true
```

## Index every foreign key and filter column

Add an index on every `*_id` column (`belongs_to` generates this automatically via `t.references`, but hand-written `add_column :foo_id` does not) and on any column used in `where`, `order`, or `joins`. Missing indexes are silent until the table grows — flagged by the code-review skill's Rails pass, but cheaper to get right at generation time.

## `belongs_to` is required by default

Rails 5+ makes `belongs_to :author` implicitly `required: true` (validates presence of the association). Use `optional: true` explicitly for nullable associations rather than relying on database nullability alone — otherwise validation and schema disagree.

## Avoid N+1 at the association level

If a view or serializer will iterate a `has_many`, load it with `includes`/`preload` at the controller level rather than letting each iteration issue its own query:

```ruby
# N+1 — one query per post
@posts = Post.all
@posts.each { |post| puts post.user.name }

# eager loaded — two queries total
@posts = Post.includes(:user)

# joins when you only need to filter, not load the association
@posts = Post.joins(:user).where(users: { active: true })
```

This matters most for index/list actions rendering a collection.

## Prefer scopes over ad-hoc class methods

```ruby
class Post < ApplicationRecord
  scope :published, -> { where(published: true) }
  scope :recent, ->(limit = 10) { order(created_at: :desc).limit(limit) }
end

Post.published.recent(5)
```

Scopes compose (`Post.published.recent`); plain class methods returning relations work too but scopes signal intent and stay chainable by convention.

## Soft delete breaks `uniqueness: true` unless scoped explicitly

Rails' `uniqueness: true` validator queries `klass.unscoped` internally — a deliberate, long-standing choice to avoid surprises with STI and default scopes — so it does **not** respect a soft-delete gem's (`acts_as_paranoid`, `discard`, ...) `default_scope` that filters out deleted rows. The practical effect: once a record is soft-deleted, its "unique" value (an email, a slug, a tag name) can never be reused, even though the record is invisible everywhere else in the app. This passes every obvious manual check (the value looks free — `Model.all` doesn't show it) and only surfaces when someone actually tries to reuse it.

Scope the validation explicitly to non-deleted rows:

```ruby
class Tag < ApplicationRecord
  acts_as_paranoid

  validates :name, presence: true, uniqueness: { conditions: -> { where(deleted_at: nil) } }
end
```

The DB-level unique index needs the same scoping, or it'll reject the reused value even after the model validation allows it — make it a partial index:

```ruby
add_index :tags, :name, unique: true, where: "deleted_at IS NULL"
```

## Enums for fixed value sets

When a column has a small fixed set of string/int values (status, role, state), use `enum` instead of free-text validation — it gives query scopes (`User.admin`), a symbolic API, and a single place to see valid values.

## Callbacks: normalization only, not business logic

Callbacks are for keeping a single record internally consistent (normalizing a field, generating a token before create) — not for slow or external work:

```ruby
class User < ApplicationRecord
  before_validation :normalize_email
  before_create :generate_token

  private

  def normalize_email
    self.email = email.downcase.strip if email.present?
  end

  def generate_token
    self.token = SecureRandom.hex(32)
  end
end
```

Sending an email, calling an external API, or processing a file from a callback (`after_create :send_welcome_email`) blocks the request on I/O the caller didn't ask to wait for — enqueue a job instead (`after_create_commit -> { WelcomeEmailJob.perform_later(id) }`). See `references/background-jobs.md`.

## Migrations

Target the Rails version actually installed (8.1 on this machine — check `db/migrate` after `rails new` for the exact version Rails stamps, don't assume):

```ruby
class CreatePosts < ActiveRecord::Migration[8.1]
  def change
    create_table :posts do |t|
      t.string :title, null: false
      t.text :body, null: false
      t.boolean :published, default: false, null: false
      t.references :user, null: false, foreign_key: true

      t.timestamps
    end

    add_index :posts, :published
  end
end
```

For backfilling existing rows rather than just changing schema, use `up`/`down` instead of `change` (data migrations generally aren't reversible in a meaningful way):

```ruby
class BackfillUsernames < ActiveRecord::Migration[8.1]
  def up
    User.where(username: nil).find_each { |user| user.update_column(:username, "user_#{user.id}") }
  end

  def down; end
end
```

## Editing a migration before it's committed can silently no-op

Editing an already-run migration's file directly (instead of adding a new migration) — the normal thing to do while Checkpoint A's models/migrations haven't been committed yet — and then rebuilding the database can silently skip the edit. `bin/rails db:create` loads the existing `db/schema.rb` when it's already stamped at the target version instead of running the migration files, so a fresh `db:drop db:create db:migrate` reports success while the columns/indexes just added to the migration never actually get created — no error, they simply don't show up. Delete `db/schema.rb` first to force real migration files to run against the fresh database:

```
rm db/schema.rb && bin/rails db:drop db:create db:migrate
```

Confirm the edit actually landed before moving on (`bin/rails runner 'puts ActiveRecord::Base.connection.columns(:tags).map(&:name)'` or similar) rather than trusting the migration output alone. Only relevant pre-commit; once a migration is committed, add a new migration instead of editing an old one, as usual.

## Concerns for cross-model behavior

Extract shared model behavior (not shared between unrelated concepts, just genuinely repeated logic) into `app/models/concerns`:

```ruby
module Sluggable
  extend ActiveSupport::Concern

  included do
    before_validation :generate_slug
    validates :slug, presence: true, uniqueness: true
  end

  private

  def generate_slug
    self.slug ||= title.parameterize if respond_to?(:title) && title.present?
  end
end

class Post < ApplicationRecord
  include Sluggable
end
```

## Batch and column-scoped queries

For anything operating over a large table, avoid loading full AR objects when you don't need them:

```ruby
User.pluck(:email)                          # array of values, no AR objects
Post.select(:id, :title, :created_at)        # only these columns hydrated
User.find_each(batch_size: 1000) { |u| ... } # loads in batches, not all at once
```
