# RSpec testing

Applies in Checkpoint C (Step 4), after `rails generate rspec:install` ran during Checkpoint A.

## FactoryBot is a default, not a requirement

Everything below assumes FactoryBot/Faker, which is the right call once a suite has enough models/associations that hand-written instantiation would repeat itself across many specs. For a small app — a handful of models, little association depth — skip the `factory_bot_rails`/`faker` gems entirely and just call `Model.create!(...)`/`Model.new(...)` with literal attributes directly in each spec. Introduce factories later if the suite grows into repeating the same instantiation across enough specs that it's worth naming once. Don't add the gems up front "because that's the convention" if nothing in the plan needs them yet.

## Setup

```ruby
# Gemfile
group :development, :test do
  gem 'rspec-rails'
  gem 'factory_bot_rails'
  gem 'faker'
end

group :test do
  gem 'shoulda-matchers'
  gem 'capybara'
  gem 'selenium-webdriver'
end

# spec/support/shoulda_matchers.rb
Shoulda::Matchers.configure do |config|
  config.integrate do |with|
    with.test_framework :rspec
    with.library :rails
  end
end
```

Rails' test environment already wraps each example in a transaction and rolls it back (`use_transactional_fixtures = true`, on by default in `rails_helper.rb`) — don't add `database_cleaner` on top of that, it's redundant with the built-in transactional rollback and just slows the suite down. It only earns its keep if a spec needs a strategy transactions can't provide (e.g. testing across `system` specs that run in a separate process/thread with a real browser, at which point add it scoped to just that need rather than suite-wide).

## Directory structure

`spec/` mirrors `app/`: `spec/models`, `spec/requests`, `spec/system`, `spec/jobs`, `spec/mailers`, plus `spec/factories`. `rails generate rspec:install` creates `spec/rails_helper.rb` and `spec/spec_helper.rb` — require `rails_helper` in specs that touch Rails, `spec_helper` only for pure Ruby.

## Model specs — validations, associations, scopes

Use `is_expected.to` / `expect(...).to`, not the older `should` syntax — pick one and stay consistent across the suite:

```ruby
RSpec.describe User, type: :model do
  describe "associations" do
    it { is_expected.to have_many(:posts).dependent(:destroy) }
    it { is_expected.to have_one(:profile).dependent(:destroy) }
  end

  describe "validations" do
    it { is_expected.to validate_presence_of(:email) }
    it { is_expected.to validate_uniqueness_of(:email).case_insensitive }
  end

  describe ".published" do
    it "excludes drafts" do
      draft = create(:post, published: false)
      live = create(:post, published: true)
      expect(Post.published).to contain_exactly(live)
    end
  end
end
```

`validate_presence_of`/`have_many` matchers come from `shoulda-matchers` — use them rather than hand-writing validation specs one assertion at a time.

## Request specs, not controller specs

Rails/RSpec favor request specs (`spec/requests`) over the older controller-spec style — they exercise the full stack (routing, middleware, rendering) and match what Rails 8 scaffolds generate:

```ruby
RSpec.describe "/posts", type: :request do
  let(:user) { create(:user) }
  before { sign_in user } # Devise::Test::IntegrationHelpers, included for type: :request specs

  describe "POST /posts" do
    it "creates a post" do
      expect { post posts_path, params: { post: { title: "Hi" } } }.to change(Post, :count).by(1)
    end

    it "rejects invalid params" do
      post posts_path, params: { post: { title: "" } }
      expect(response).to have_http_status(:unprocessable_entity)
    end
  end
end
```

For an API-only app, assert on JSON body and status code instead of redirects. `sign_in` requires `config.include Devise::Test::IntegrationHelpers, type: :request` in `rails_helper.rb` (added by `rails generate devise:install`, but confirm it's there before relying on it).

## System specs for full user flows

Use `spec/system` (Capybara + a headless driver) sparingly, for flows that cross multiple pages and matter end-to-end — sign up → confirm → log in, checkout, onboarding:

```ruby
RSpec.describe "Creating a post", type: :system do
  before { driven_by(:selenium_chrome_headless) }

  it "allows a signed-in user to create a post" do
    user = create(:user)
    sign_in user
    visit new_post_path

    fill_in "Title", with: "My New Post"
    click_button "Create Post"

    expect(page).to have_content("Post was successfully created")
  end
end
```

Not a substitute for request specs on individual endpoints; slower and more brittle, so reserve for the handful of flows that justify it.

## FactoryBot over fixtures

Define factories in `spec/factories/` mirroring model names, using `Faker` for realistic-but-fake data and traits for variants:

```ruby
FactoryBot.define do
  factory :user do
    email { Faker::Internet.email }
    password { "Password123!" }

    trait :admin do
      role { :admin }
    end
  end

  factory :post do
    title { Faker::Lorem.sentence }
    association :user

    trait :published do
      published { true }
    end
  end
end
```

## Shared examples for repeated behavior

When the same behavior (e.g. "requires sign-in") applies across several request specs, extract it instead of repeating the `context` block:

```ruby
# spec/support/shared_examples/authenticatable.rb
RSpec.shared_examples "authenticatable" do
  context "when not signed in" do
    it "redirects to sign in" do
      make_request
      expect(response).to redirect_to(new_user_session_path)
    end
  end
end

RSpec.describe "/admin/posts", type: :request do
  include_examples "authenticatable" do
    let(:make_request) { get admin_posts_path }
  end
end
```

## Testing jobs and mailers

```ruby
RSpec.describe WelcomeEmailJob, type: :job do
  it "delivers the welcome email" do
    user = create(:user)
    expect { described_class.perform_now(user.id) }
      .to change { ActionMailer::Base.deliveries.count }.by(1)
  end
end

RSpec.describe UserMailer, type: :mailer do
  describe "#welcome_email" do
    let(:mail) { UserMailer.welcome_email(create(:user)) }

    it "renders the headers" do
      expect(mail.subject).to eq("Welcome!")
    end
  end
end
```

## Test behavior, not implementation

Assert on observable outcomes (response status/body, DB state, redirected path, enqueued jobs) rather than internal method calls, unless the spec is specifically about a collaborator being invoked correctly.
