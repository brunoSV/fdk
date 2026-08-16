# API development

Applies when Step 2's stack answer is API-only Rails (`--api` scaffold flag) with REST as the API style. For GraphQL, see `references/graphql-api.md` instead — auth, CSRF, and CORS below still apply to either style.

## What `--api` changes

`ApplicationController` inherits from `ActionController::API`, not `ActionController::Base` — no view rendering, no helpers, no asset pipeline, and a slimmer middleware stack (no cookie/session/flash middleware by default). CSRF protection is off by default because there's no session-backed HTML form to forge.

## Building a session-based admin panel inside an `--api` app

Checkpoint A's admin panel (plain server-rendered Rails views, even when the main stack is API + frontend) needs three things back that `config.api_only = true` removes, beyond the middleware note above:

1. **Re-add the session/cookie/flash middleware**, scoped to the reason, in `config/application.rb`:
   ```ruby
   # The /admin panel is server-rendered with session-based Devise auth, so it
   # needs the session/cookie/flash middleware that API-only mode strips out.
   config.middleware.use ActionDispatch::Cookies
   config.middleware.use ActionDispatch::Session::CookieStore
   config.middleware.use ActionDispatch::Flash
   ```
   Give the admin controllers their own base class inheriting `ActionController::Base` (not the API-only `ApplicationController`) so they get view rendering and this middleware's helpers.

2. **`resources` drops `:new` and `:edit` by default under `config.api_only = true`** (API clients don't need HTML form endpoints) — so `resources :posts, except: [:show]` silently omits the new/edit routes an admin panel's forms need. List the actions explicitly instead: `resources :posts, only: [:index, :new, :create, :edit, :update, :destroy]`.

3. **Devise's `set_flash_message!` raises `undefined method 'flash'`** on any Devise controller whose parent chain resolves back to the API-only `ApplicationController` — this hits the admin's session controller if it isn't based on the `ActionController::Base` admin base class, and it separately hits any JSON-only auth controller built for the JWT-authenticated resource below (see that section). Override it to a no-op wherever there's no page to flash a message onto:
   ```ruby
   def set_flash_message!(*); end
   ```

## Auth: Devise defaults to cookie sessions

Devise's default `:database_authenticatable` module assumes a browser session. For a pure JSON API consumed by a separate frontend, add `devise-jwt` on top rather than hand-rolling token auth — it plugs into the Devise/Warden flow already generated in Step 4 instead of replacing it:

```ruby
# Gemfile
gem 'devise-jwt'

# app/models/user.rb
devise :database_authenticatable, :registerable, :jwt_authenticatable,
       jwt_revocation_strategy: self
include Devise::JWT::RevocationStrategies::JTIMatcher

# config/initializers/devise.rb
config.jwt do |jwt|
  jwt.secret = Rails.application.credentials.secret_key_base
  jwt.dispatch_requests = [['POST', %r{^/api/v1/login$}]]
  jwt.revocation_requests = [['DELETE', %r{^/api/v1/logout$}]]
  jwt.expiration_time = 24.hours.to_i
end
```

With this in place, `before_action :authenticate_user!` and `current_user` work the same as in a Hotwire app — no separate hand-written authentication concern needed. Use Doorkeeper instead if the API needs full OAuth2 (third-party clients, scoped tokens) rather than just "the frontend holds a token."

If sign-up/sign-in need custom JSON-only controllers (`Api::V1::SessionsController < Devise::SessionsController`, `Api::V1::RegistrationsController < Devise::RegistrationsController`) to shape the response body, they'll hit the `set_flash_message!` crash from the admin-panel section above too — same fix, a no-op override, since there's no HTML page to flash a message onto here either.

Skip token auth entirely if the "separate frontend" is actually server-rendered from the same Rails app on a different route namespace — then session cookies still work.

## CSRF when the API isn't `--api`-only

If JSON/GraphQL routes are mounted on a full (non-`--api`) Rails app alongside HTML views — see Step 2's CSRF question in SKILL.md — scope the exemption narrowly:

```ruby
class Api::BaseController < ApplicationController
  skip_before_action :verify_authenticity_token, if: -> { request.format.json? }
end
```

Don't exempt at the `ApplicationController` level; that silently covers every future HTML mutation too.

## Versioning and structure

Namespace under `/api/v1` from the start even with one version — retrofitting a version prefix later breaks every existing client:

```ruby
# config/routes.rb
namespace :api do
  namespace :v1 do
    resources :posts
  end
end

# app/controllers/api/v1/posts_controller.rb
module Api
  module V1
    class PostsController < ApplicationController
      before_action :set_post, only: [:show, :update, :destroy]

      def index
        @posts = Post.includes(:user).page(params[:page])
        render json: @posts
      end

      def create
        @post = current_user.posts.build(post_params)
        if @post.save
          render json: @post, status: :created
        else
          render json: { errors: @post.errors }, status: :unprocessable_entity
        end
      end

      private

      def set_post
        @post = Post.find(params[:id])
      end

      def post_params
        params.require(:post).permit(:title, :body, :published)
      end
    end
  end
end
```

For pagination, `page`/`per` above assumes a pagination gem (Kaminari or Pagy) — pick one rather than hand-rolling `limit`/`offset`, and only add it once a list endpoint's result set is actually unbounded.

## Serialization

For a handful of simple resources, `render json: @post` (backed by `as_json`/`to_json` overrides on the model) is enough. Once responses need consistent envelopes, conditional attributes, or nested associations across many endpoints, introduce a serializer gem (Blueprinter or `active_model_serializers`) rather than hand-rolling `as_json` everywhere — pick this based on the number of distinct resource shapes the plan calls for, not preemptively.

## Errors

Centralize exception handling in a concern included by `ApplicationController`, rather than repeating `rescue_from` per controller:

```ruby
# app/controllers/concerns/error_handler.rb
module ErrorHandler
  extend ActiveSupport::Concern

  included do
    rescue_from ActiveRecord::RecordNotFound, with: :not_found
    rescue_from ActionController::ParameterMissing, with: :bad_request
  end

  private

  def not_found(exception)
    render json: { error: exception.message }, status: :not_found
  end

  def bad_request(exception)
    render json: { error: exception.message }, status: :bad_request
  end
end
```

## CORS

If the frontend is served from a different origin, add `rack-cors` and configure allowed origins in `config/initializers/cors.rb` — otherwise browser requests fail silently at the network layer, which is a confusing first bug to debug:

```ruby
# Gemfile
gem 'rack-cors'

# config/initializers/cors.rb
Rails.application.config.middleware.insert_before 0, Rack::Cors do
  allow do
    origins ENV.fetch("FRONTEND_ORIGIN", "localhost:3000")
    resource "*", headers: :any, methods: [:get, :post, :put, :patch, :delete], credentials: true
  end
end
```

## Optional: rate limiting and documentation

Add only if the plan calls for it — neither is part of the baseline:

- `rack-attack` to throttle abusive traffic (e.g. login attempts by IP/email).
- `rswag` to generate OpenAPI docs from request specs, if the API has external consumers who need published documentation.
