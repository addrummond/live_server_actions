# Quotes

This example presents the user with a choice of fruits via a dropdown. When a
button is pressed, a server action is called which returns an inspirational
quote about the chosen fruit.

## assets/js/quotes.tsx
```tsx
import React from "react"
import { serverActions } from "live_server_actions";
import { useState, useActionState, startTransition } from 'react';

export const RandomQuoteChooser = () => {
  const [fruit, setFruit] = useState("Apple");
  const [quote, getQuoteAction] = useActionState(
    () => serverActions.QuotesWeb.MainLive.get_quote({ fruit }),
    null
  );

  return <div>
    <p><label htmlFor="fruit">Choose a fruit:</label></p>
    <select id="fruit" name="fruit" onChange={e => setFruit(e.target.value)} value={fruit}>
      <option value="Apple">Apple</option>
      <option value="Pineapple">Pineapple</option>
      <option value="Pear">Pear</option>
    </select>
    <Quote quote={quote} />
    <p>
      <button
        type="button"
        className="py-2 px-4 bg-zinc-900 text-white font-semibold rounded-lg shadow-md focus:outline-none focus:ring-2 focus:ring-green-400 focus:ring-opacity-75"
        onClick={() => {
          startTransition(() => {
            getQuoteAction();
          });
        }}
      >
        Load {quote ? "another" : "a"} quote
      </button>
    </p>
  </div>
};

function Quote({ quote }) {
  return quote && <div>
    <p><i>{quote.quote}</i></p>
    <p>– {quote.author} ({quote.year})</p>
  </div>
}
```

## assets/js/app.js
```javascript
import React from "react"
import { createRoot } from 'react-dom/client';
import { addHooks, addComponentLoader } from "live_server_actions";
import { RandomQuoteChooser } from "./quotes.tsx"

let Hooks = { };
//
// ...your other hooks here...
//
addHooks(Hooks);

// Copy/paste this class into your app. Implementation details will vary
// depending on React version. This code is for React 19.0. The
// live_server_actions module has no React dependency, so you can use it with
// any version of React.
class ReactComponentLoader {
  constructor(component) {
    this.component = component;
  }

  load(rootElem, props) {
    this.root = createRoot(rootElem);
    Promise.resolve(this.component).then(c =>
      this.root.render(React.createElement(c, props))
    );
  }

  unload(_rootElem) {
    this.root.unmount();
  }
}

addComponentLoader("RandomQuoteChooser", new ReactComponentLoader(RandomQuoteChooser));

// ...

// Add the 'hooks' option in the LiveSocket constructor
let liveSocket = new LiveSocket("/live", Socket, {
  hooks: Hooks,
  longPollFallbackMs: 2500,
  params: {_csrf_token: csrfToken}
})

// ...
```

## lib/counter_web/live/quotes_live.ex
```elixir
defmodule QuotesWeb.QuotesLive do
  use Phoenix.LiveView
  use LiveServerActions

  alias LiveServerActions.Components

  @quotes_database %{
    "pineapple" => [
      "Like the tough exterior of a pineapple, our challenges shape us, but they cannot define us – for within lies sweetness and strength.",
      "Life is like a pineapple upside-down cake - messy, imperfect, yet beautifully transformed by the heat of our experiences.",
      "Just as the pineapple plant grows new fruit from its own crown, may you cultivate resilience, renewal, and growth from within, rising stronger with each new challenge."
    ],
    "pear" => [
      "Just as a pear ripens with time, so too do our experiences shape us into the best version of ourselves.",
      "Life is like a pear tree - it requires patience, nurturing, and trust that the sweetness will come.",
      "Just as the tender skin of a pear protects the treasure within, may your resilience shield your heart and soul, allowing your true beauty to shine."
    ],
    "apple" => [
      "Like an apple seed, our smallest actions hold the potential to grow into something extraordinary.",
      "Life is like biting into a crisp apple - unexpected, refreshing, and full of hidden sweetness.",
      "Just as an apple tree blossoms in seasons of change, may you find strength in transformation and beauty in every stage of life."
    ]
  }

  @authors [
    "Mark Twain",
    "Jane Austen",
    "William Shakespeare",
    "Charles Dickens",
    "Ernest Hemingway",
    "F. Scott Fitzgerald",
    "George Orwell",
    "J.K. Rowling",
    "Agatha Christie",
    "J.R.R. Tolkien"
  ]

  def render(assigns) do
    ~H"""
    <Components.react_component id="my-fruit-quoter" component="RandomQuoteChooser" />
    """
  end

  @server_action true
  @spec get_quote(Phoenix.LiveView.Socket.t(), %{fruit: String.t()}) ::
          %{error: String.t()}
          | %{quote: String.t(), author: String.t(), year: integer()}
  defp get_quote(_socket, %{fruit: fruit}) do
    fruit = String.downcase(fruit)

    if Map.has_key?(@quotes_database, fruit) do
      %{
        quote: Enum.random(@quotes_database[fruit]),
        author: Enum.random(@authors),
        year: Enum.random(1000..2024)
      }
    else
      %{error: "I don't have any quotes for that fruit."}
    end
  end
end
```

## lib/counter_web/router.ex
Before `get "/", PageController, :home`:

```elixir
live "/", QuotesLive
```
