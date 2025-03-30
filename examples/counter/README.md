# Counter

This example is a classic React counter demo, but with a counter that is
stored on the server in an
[ETS table](https://elixirschool.com/en/lessons/storage/ets).

Clicking the button calls a server action which increments the counter and then
returns the new counter value to the client.

## assets/js/counter.tsx
```tsx
import React from 'react';
import { serverActions } from "live_server_actions";
import { useState, useEffect } from 'react';

const CounterLive = serverActions.CounterWeb.CounterLive;

export const Counter = () => {
  const [count, setCount] = useState(null);

  // Get the initial count by incrementing by 0
  useEffect(
    () => void CounterLive.update_count(0).then(
      ({new_count}) => { setCount(new_count); }
    ),
    [count]
  );

  return <div>
    <p>Count: {count}</p>
    <button onClick={() => {
      CounterLive.update_count(1).then(
        ({new_count}) => { setCount(new_count); }
      );
    }}>Increment</button>
  </div>;
};
```

## assets/js/app.js
```javascript
import React from "react"
import { createRoot } from 'react-dom/client';
import { addHooks, addComponentLoader } from "live_server_actions";
import { Counter } from "./counter.tsx"

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

  update(props) {
    this.root.render(React.createElement(this.component, props));
  }

  unload() {
    this.root.unmount();
  }
}

// load this way if component is already imported
addComponentLoader("Counter", new ReactComponentLoader(Counter));

// load this way if you want to load the component dynamically
//addComponentLoader("Counter", new ReactComponentLoader(import("./counter").then(m => m.Counter)));

// ...

// Add the 'hooks' option in the LiveSocket constructor
let liveSocket = new LiveSocket("/live", Socket, {
  hooks: Hooks,
  longPollFallbackMs: 2500,
  params: {_csrf_token: csrfToken}
})

// ...
```

## inside lib/counter/application.ex
```elixir
...
@impl true
def start(_type, _args) do
  # initialize ETS table for storing counter value
  :ets.new(:counter, [:set, :public, :named_table])
  :ets.insert(:counter, {:counter, 0})
  ...
end
...
```

## lib/counter_web/live/counter_live.ex
```elixir
defmodule CounterWeb.CounterLive do
  use Phoenix.LiveView
  use LiveServerActions

  alias LiveServerActions.Components

  def mount(_params, _session, socket) do
    {:ok, assign(socket, count: 0)}
  end

  def render(assigns) do
    ~H"""
    <Components.react_component id="my-counter" component="Counter" />
    """
  end

  @server_action true
  @spec update_count(Phoenix.LiveView.Socket.t(), integer()) :: %{new_count: integer()}
  defp update_count(_socket, inc) do
    %{new_count: :ets.update_counter(:counter, :counter, inc)}
  end
end
```

## lib/counter_web/router.ex
Before `get "/", PageController, :home`:

```elixir
live "/", CounterWeb.CounterLive
```
