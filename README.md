# LiveServerActions

Call Elixir functions from React, with optional type safety.

Inspired by Next.js
[server actions](https://nextjs.org/docs/app/building-your-application/data-fetching/server-actions-and-mutations).

## Features

* Built on LiveView events.
* Expose Elixir functions to the frontend as JavaScript async functions.
* Optional type safety via automatic generation of Typescript `.d.ts` files
  from Elixir type specs.
* Server actions are compatible with `useActionState`.
* Lightweight and dependency free:
  * Use with **any React version** and **any JS bundler**.
  * Adds just ~150 lines of unminified JS to your client bundle.
  * No generated JS code.
  * No (non-dev) npm dependencies.

## Setup

* Add the following dependency to `mix.exs`:
```elixir
{:live_server_actions, "~> 0.3.2"}
```
* Add the following dependency to your `package.json`:
```json
"live_server_actions": "file:deps/live_server_actions"
```
* `mix deps.get && npm i`.
* Ensure that you have a `tsconfig.json` file in `assets` if you want to use
  Typescript.
* *(optional)* Add the pattern `LiveServerActions__*.d.ts` to your `.gitignore` if
  you don't want to check in the generated Typescript type definitions.
* Look at one of the [examples](#examples) to see how to set up your `app.js`
(e.g. [examples/counter/assets/js/app.js](examples/counter/README.md#assetsjsappjs)).

## Defining server actions

Use `LiveServerActions` inside your LiveView module and then
define a function tagged with `@server_action true`:

```elixir
defmodule MyAppWeb.FooLive do
  use Phoenix.LiveView
  use LiveServerActions

  ...

  @server_action true
  defp get_user_roles(_socket, %{ "user_uuid" => user_uuid }) do
    roles = Users.get_roles(user_uuid)
    %{ roles: roles }
  end
end
```

The first argument to a server action is always the LiveView's live socket.
This argument is not present when the function is called from the client.
On the client, `serverActions.MyAppWeb.FooLive.get_user_roles` is
an async function called as follows:

```typescript
import { serverActions } from "live_server_actions"

serverActions.MyAppWeb.FooLive.get_user_roles({ user_uuid: "abc-xyz" }).then(({ roles } => {
  ...
});
```

You can use type specs to export type information to Typescript:

```elixir
@server_action true
@spec get_user_roles(Phoenix.LiveView.Socket.t(), %{ user_uuid: String.t() }) :: %{roles: [String.t()]}
defp get_user_roles(_socket, %{ user_uuid: user_uuid }) do
  roles = Users.get_roles(user_uuid)
  %{ roles: roles }
end
```

An equivalent type is now defined for
`serverActions.MyAppWeb.FooLive.get_user_roles`
(see [next section](#generated-typescript-dts-files)).

Notice that the typed version of the function receives a map with the atom key
`:user_uuid` rather than the string key `"user_uuid"`. This is because of
[automatic string to atom munging](#automatic-string-to-atom-munging).

LiveServerActions doesn't care about the type of the `socket` argument, so if
you want to save some typing, you can replace `Phoenix.LiveView.Socket.t()`
with `any()`.

Server actions may be defined as either public or private functions. The choice
is a question of style left to the user. It has no effect on the server action's
functionality.

If you name function arguments then these names are exported to the
corresponding Typescript type definition. For example, the following server
actions all have a second argument named `options`:

```elixir
@server_action true
defp my_server_action1(_socket, _options=%{protocol: protocol}) do
  ...
end

@server_action true
defp my_server_action2(_socket, %{protocol: protocol}=options) do
  ...
end

@server_action true
defp my_server_action2(_socket, options) do
  ...
end
```

### Generated TypeScript .d.ts files

When a server action module `MyApp.FooLive` is compiled, a corresponding
`LiveServerActions__MyApp.FooLive.d.ts` file is emitted in the `assets/js`
folder. This file specifies the methods available for
`serverActions.MyApp.FooLive`, and the type of each method if the corresponding
Elixir function has a type spec.

Emission of `.d.ts` files only occurs when `Mix.env() == :dev`.

You can pass the `d_ts_output_dir` option to `use LiveServerActions` to change
the output directory for `.d.ts` files:

```elixir
use LiveServerActions, d_ts_output_dir: "/foo/bar"

# set a path relative to the project root dir
use LiveServerActions, d_ts_output_dir: fn root -> Path.join([root, "assets", "js"]) end
```

You can also customize the full path and filename of each individual `.d.ts`
file based on the module name:

```elixir
use LiveServerActions, get_d_ts_filename: fn output_dir, module_name ->
  Path.join([output_dir, "MyPrefix__#{module_name}.d.ts"])
end
```

The second parameter to the function is the module name as a string with the
`"Elixir."` prefix removed.

If you want to disable generation of `.d.ts` files, you can set
`d_ts_output_dir` to `false`.

### Serialization

Values are serialized before being passed to server actions or returned to the
client. At present, the following values are serializable:

* **JavaScript**
  * Numbers
  * Strings
  * Booleans
  * `null`
  * Objects with the keys/values given by `Object.entries()`, where all values
    are serializable
  * Arrays of serializable values
  * `Set` objects with serializable non-object members (converted to Elixir
    `MapSet` values).
  * `Map` objects where keys are strings or numbers and values are serializable
    (converted to Elixir maps)
  * `FormData` objects where values are strings.
  * `Date` objects (converted to Elixir `DateTime` structs)
* **Elixir**
  * Integers
  * Floats
  * Strings (i.e. binaries)
  * Booleans
  * `nil`
  * Maps with string or atom keys and serializable values
  * `MapSet`s containing integers, floats, strings, booleans or `nil` (converted
    to JavaScript `Set` objects).
  * Lists of serializable values
  * `DateTime` or `Date` structs (converted to JavaScript `Date` objects)

In future, support may be added for customizing encoding/decoding of values. The
restrictions on serialization of sets are imposed because JavaScript `Set` and
Elixir `MapSet` have quite different identity semantics. For example, in
JavaScript, `new Set([new Set([1]), new Set([1])])` is a set with two members,
whereas in Elixir, `MapSet.new([MapSet.new([1]), MapSet.new([1])])` is a set
with one member.

### Updating the live socket

A typical server action will retrieve a value from the database and then return it.
However, in some instances, you might want a server action to update the live socket
(for example, to update `socket.assigns`). In this case, you can return a
`{socket, return_value}` tuple from your server action. The tuple is automatically
stripped before the return value is serialized and sent back to the client.

### Form data

You can use live server actions and `useActionState` to set the `action`
property of a `<form>`:

```tsx
const [formState, formAction] = useActionState(
  (_currentState, formData) =>
    serverActions.MyAppWeb.FooLive.submit_form(formData)),
  {}
);

<form action={formAction}>
  <input type="text" name="foo" size="30" />

  {/* formState is updated when form is submitted */}
  <button type="submit">Submit</button>
</form>
```

```Elixir
@server_action true
defp submit_form(socket, form_data=%{}) do
  # this becomes the new value of formState above
  %{foo: "bar"}
end
```

### Other notes on server actions

* Calls to a server action translate to calls to
  [`pushEvent`](https://hexdocs.pm/phoenix_live_view/js-interop.html#client-hooks-via-phx-hook).
  All the usual
  [security considerations](https://hexdocs.pm/phoenix_live_view/security-model.html)
  relating to LiveView sockets apply here.
* If a server action raises an exception, a message is sent to the client
  causing the associated promise to be rejected.
* Type checking is **not** performed on the server side. Adding a type spec for
  a server action prevents Typescript code from calling the action with
  bad arguments, but does not protect against an attacker sending mistyped data.
* Calling a server action in a different LiveView module will give rise to a
  runtime error on the server.
* A server action must have only one function clause. The library will raise an
  error at compile time if this constraint is broken.

## Embedding a React component in your LiveView

In your LiveView:

```elixir
defmodule MyAppWeb.FooLive do
  use Phoenix.LiveView
  use LiveServerActions

  alias LiveServerActions.Components

  def render(assigns) do
    ~H"""
    <Components.react_component id="my-react-component-id" component="MyReactComponent" />
    """
  end
end
```

In your `app.js`:

```javascript
import { addHooks, addComponentLoader } from "live_server_actions";
import { MyReactComponent } from "./my_react_component";

...
addHooks(Hooks);
...

// For React 19. Change as appropriate for your React version.
class ReactComponentLoader {
  constructor(component) {
    this.component = component;
  }

  load(rootElem, props) {
    this.root = createRoot(rootElem);
    Promise.resolve(this.component).then(c => {
      this.component = c;
      this.root.render(React.createElement(c, props))
    });
  }

  update(props) {
    this.root.render(React.createElement(this.component, props));
  }

  unload() {
    this.root.unmount();
  }
}

// The first argument to this function corresponds to the value
// of the 'component' attr of the Components.react_component component.
addComponentLoader("MyReactComponent", new ReactComponentLoader(MyReactComponent));

// load this way if you want to load the component dynamically
//addComponentLoader("MyReactComponent", new ReactComponentLoader(import("./my_react_component").then(m => m.MyReactComponent)));
```

## Examples

The `examples` dir contains two simple Phoenix apps using LiveServerActions.
To demo the apps:
* Go to the app dir
* Run `mix deps.get && npm i && mix phx.server`
* Go to `http://localhost:4000`

### Example 1: a simple counter updated on the server

This example is a classic React counter demo, but with a counter that is
stored on the server in an
[ETS table](https://elixirschool.com/en/lessons/storage/ets).

Clicking the button calls a server action which increments the counter and then
returns the new counter value to the client.

See `examples/counter` in this repo and [this readme](examples/counter/README.md).

### Example 2: loading a random quote when a button is pressed

This example presents the user with a choice of fruits via a
dropdown. When a button is pressed, a server action is called which returns
an inspirational quote about the chosen fruit.

See `examples/quotes` in this repo and [this readme](examples/quotes/README.md).

## Typing

### The Typescript fallback type

If no Typescript equivalent is defined for an Elixir type, or if no `@spec` was
defined for a server action, then `any` is used by default as a fallback type
for arguments and return values. You can change this default to `unknown`:

```elixir
use LiveServerActions, typescript_fallback_type: :unknown
```

You can also override this default on a per-server-action basis:

```elixir
@server_action [typescript_fallback_type: :unknown]
@spec my_server_action(...) :: ...
def my_server_action(...) do
  ...
end
```

### Automatic string to atom munging

Elixir's type spec syntax does not allow the specification of maps with
particular string keys. To work around this limitation, maps with string keys
are automatically converted to maps with atom keys if the server action is
given a suitable type spec.

To illustrate, consider the following server action. When `get_email_address`
is called from JavaScript, it will be passed a JavaScript object of the form
`{user_uuid: "xyz-abc"}`. This then translates to the Elixir map
`%{ "user_uuid" => "xyz-abc" }`. However, because the type spec defines the
second argument of the function as a map with the key `user_uuid`, this map is
automatically converted to `%{ user_uuid: "xyx-abc" }` before being passed to
the function.

```elixir
@server_action true
@spec get_email_address(
  Phoenix.LiveView.Socket.t(),
  %{user_uuid: String.t()}
) :: %{error: String.t()} | %{email: String.t() }
defp get_email_address(_socket, %{user_uuid: user_uuid}) do
  ...
end
```

If you want to avoid auto-munging, use the type `map()` instead of specifying
specific keys (or just don't add a type spec at all). For example, the following
server action receives `%{ "user_uuid" => "xyz-abc" }`:

```elixir
@server_action true
@spec get_email_address(
  Phoenix.LiveView.Socket.t(),
  map()
) :: %{error: String.t()} | %{email: String.t() }
defp get_email_address(_socket, %{"user_uuid" => user_uuid}) do
  ...
end
```

The choice of string keys or atom keys does not matter for the return value of
a server function, as both `%{foo: "bar"}` and `%{ "foo" => "bar" }` are
converted to the JavaScript object `{foo: "bar"}`.
