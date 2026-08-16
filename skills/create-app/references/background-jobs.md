# Background jobs

Applies when Step 2 identifies async work (emails, imports, third-party API calls).

## Solid Queue is the Rails 8 default

No extra gem, no Redis. `rails new` on Rails 8 already wires `config.active_job.queue_adapter = :solid_queue` and a `solid_queue` database/schema. Don't add Sidekiq or `sucker_punch` unless the product has a specific reason (existing infra, a feature Solid Queue lacks) — it's unnecessary weight, and an extra Redis dependency, on a fresh app.

## Defining a job

```ruby
class ImportOrdersJob < ApplicationJob
  queue_as :default

  def perform(source_id)
    # ...
  end
end
```

Enqueue with `ImportOrdersJob.perform_later(source.id)` — pass IDs, not full records, so the job re-fetches fresh state at execution time rather than serializing a stale object.

Delay or schedule a specific run time without touching `recurring.yml`:

```ruby
ImportOrdersJob.set(wait: 1.hour).perform_later(source.id)
ImportOrdersJob.set(wait_until: Date.tomorrow.noon).perform_later(source.id)
```

## Queue priority

Solid Queue processes queues in the order listed in `config/queue.yml` (or by `--queue` args to `bin/jobs`). Give urgent work its own queue rather than tuning `wait`:

```ruby
class SendPasswordResetJob < ApplicationJob
  queue_as :critical
end

class GenerateMonthlyReportJob < ApplicationJob
  queue_as :low
end
```

## Retries and failure handling

```ruby
class ImportOrdersJob < ApplicationJob
  retry_on Net::ReadTimeout, wait: :polynomially_longer, attempts: 5
  discard_on ActiveRecord::RecordNotFound
end
```

Default behavior without `retry_on`/`discard_on` is to retry indefinitely on any error, which can silently hammer a failing external API — always set explicit retry/discard rules for jobs that call third-party services.

## Idempotency

Jobs can run more than once (a retry after a partial failure, a duplicate enqueue). Guard against redoing work rather than assuming single delivery:

```ruby
class ProcessOrderJob < ApplicationJob
  def perform(order_id)
    order = Order.find(order_id)
    return if order.processed?

    order.process!
  end
end
```

## What belongs in a job vs. a model callback

Anything slow or external — emails, API calls, image processing, file parsing — belongs in a job, not an `after_save` callback. A callback doing this work blocks the request/response cycle (or the console session that triggered the save) on I/O the caller didn't ask to wait for. This is the "fat callbacks" pattern the code-review skill's Rails pass flags — see `references/active-record.md`'s callbacks section for the model-side half of this.

```ruby
# in the model
after_create_commit -> { NotifyOwnerJob.perform_later(id) }
```

Use `after_create_commit`, not `after_create` — firing before the transaction commits risks the job running against a record that isn't visible yet if it queries via a different connection.

## Recurring jobs

Solid Queue supports scheduled/recurring jobs via `config/recurring.yml`:

```yaml
production:
  cleanup_expired_tokens:
    class: CleanupExpiredTokensJob
    schedule: every day at 3am
```

Only add this if the plan actually calls for scheduled work — don't scaffold it speculatively.

## Testing

```ruby
RSpec.describe ImportOrdersJob, type: :job do
  it "enqueues on the default queue" do
    expect { ImportOrdersJob.perform_later(1) }
      .to have_enqueued_job(described_class).with(1).on_queue("default")
  end

  it "processes the source" do
    source = create(:order_source)
    expect { described_class.perform_now(source.id) }
      .to change { source.reload.orders.count }
  end
end
```

`config.active_job.queue_adapter = :test` is set automatically in the test environment, so `perform_later` doesn't actually run jobs — use `perform_now` (or `perform_enqueued_jobs`) when a spec needs the side effects, and `have_enqueued_job` when it only needs to confirm the enqueue.
