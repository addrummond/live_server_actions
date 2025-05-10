# LiveServerActions changelog

## 0.3.1

* Fix bug with syntax of function argument types in emission of `.d.ts` files
  (e.g. `(number, number)` instead of `(arg1: number, arg2: number)`).

## 0.3.0

* Fix bug with `null` arguments to server actions.
* Better serialization/deserialization algorithm.

## 0.2.0

* Expands range of serializable values to include JavaScript `Set`, `Map` and
`FormData` objects and Elixir `MapSet` values.

## 0.1.1

* Initial release (superseded v0.1.0 after only a few minutes).
