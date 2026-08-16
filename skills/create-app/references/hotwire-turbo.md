# Hotwire / Turbo

Applies when Step 2's stack answer is Hotwire (server-rendered views, no separate frontend).

## No Node.js on this machine

The default Rails 8 JS setup is importmap-based (`config/importmap.rb`, no bundler, no `node_modules`) and that's what this environment supports out of the box. If a requirement genuinely needs a JS build step — React, a chart library requiring a bundler, esbuild-only packages — flag it during Step 2 rather than discovering the missing Node install mid-scaffold; that's a stack deviation the user needs to approve, not something to silently work around.

## Turbo Drive

On by default with `rails new` — turns full-page navigations into AJAX-style requests without any code. A controller action just needs to render the right response for the request to feel instant:

```ruby
def create
  @article = Article.new(article_params)

  if @article.save
    redirect_to @article, notice: "Article created!"
  else
    render :new, status: :unprocessable_entity
  end
end
```

## Turbo Frames — scoped partial updates

Wrap a region in a frame; links/forms inside it replace only that region instead of the whole page. The `show` and `edit` views can share the same frame ID so navigating between them only swaps that region:

```erb
<%# app/views/articles/show.html.erb %>
<%= turbo_frame_tag dom_id(@article) do %>
  <h1><%= @article.title %></h1>
  <%= link_to "Edit", edit_article_path(@article) %>
<% end %>
```

Lazy-load an expensive frame instead of blocking the initial render:

```erb
<%= turbo_frame_tag "expensive_content", src: expensive_content_path, loading: :lazy %>
```

Good for inline edit, pagination within a section, or a sidebar that updates independently of the main content.

## Turbo Streams — real-time / multi-client updates

For updates that should broadcast to other connected clients (not just the requester), broadcast from the model:

```ruby
class Comment < ApplicationRecord
  belongs_to :post
  broadcasts_to :post
end
```

Add `<%= turbo_stream_from @post %>` in the view to subscribe. `broadcasts_to` covers the common create/update/destroy case; for anything more custom, broadcast explicitly from a callback instead:

```ruby
after_create_commit -> { broadcast_append_to post, target: "comments" }
```

For updates scoped to just the current request/response (e.g. a form submission that should update the page without a full reload, with nothing to broadcast to other viewers), respond with `turbo_stream` format from the controller action instead — no broadcasting/websocket needed for that case:

```ruby
def create
  @comment = @article.comments.create(comment_params)
  respond_to do |format|
    format.turbo_stream
    format.html { redirect_to @article }
  end
end
```

The seven stream actions: `append`, `prepend`, `replace`, `update`, `remove`, `before`, `after` — e.g. `turbo_stream.append "comments", partial: "comments/comment", locals: { comment: @comment }`.

## Stimulus for JS behavior

Controllers live in `app/javascript/controllers/`, registered automatically via the importmap-pinned `controllers/index.js` that `rails new` generates:

```javascript
// app/javascript/controllers/dropdown_controller.js
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["menu"]

  toggle() {
    this.menuTarget.classList.toggle("hidden")
  }
}
```

```erb
<div data-controller="dropdown">
  <button data-action="dropdown#toggle">Menu</button>
  <div data-dropdown-target="menu" class="hidden">...</div>
</div>
```

Use it for small, targeted interactivity (toggle, autosubmit, character counter, a client-side validation hint) — not as a place to grow a client-side app; that's the signal the product actually needs the API + separate-frontend stack instead.

## Common patterns

Inline editing, swapping a display frame for an edit frame at the same DOM ID:

```erb
<%= turbo_frame_tag dom_id(@article, :title) do %>
  <%= link_to @article.title, edit_article_path(@article), data: { turbo_frame: dom_id(@article, :title) } %>
<% end %>
```

A modal driven by navigating into an empty frame:

```erb
<%= turbo_frame_tag "modal" %>
<%= link_to "Open Modal", new_article_path, data: { turbo_frame: "modal" } %>
```

## Performance tips

- Use `loading: :lazy` for off-screen frames rather than loading everything on first paint.
- Debounce Stimulus actions driving search/autocomplete requests.
- Keep frame nesting shallow — deeply nested frames get harder to reason about which region updates on a given action.
