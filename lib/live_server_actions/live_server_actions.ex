defmodule LiveServerActions do
  @moduledoc """
  Add `use LiveServerActions` to your module to enable server actions.

  Server actions may be public or private functions, and must have the attribute
  `@server_action true`.
  """

  alias LiveServerActions.Helpers

  defmacro __using__(args \\ []) do
    quote do
      if String.contains?("#{unquote(__MODULE__)}", "__") do
        raise Helpers.make_module_name_double_underscore_error(__MODULE__)
      end

      @on_definition unquote(__MODULE__)
      @before_compile unquote(__MODULE__)
      @after_compile unquote(__MODULE__)

      @__live_server_actions_typescript_fallback_type unquote(
                                                        args[:typescript_fallback_type] || :any
                                                      )
      @__live_server_actions %{}

      # make sure this is defined at least once with a guard that won't match
      # anything
      defp __live_server_actions_call_private_server_action(nil, nil), do: nil
    end
  end

  def __on_definition__(%{module: module}, kind, name, args, _guards, _body)
      when kind in [:def, :defp] do
    sact_attr = Module.get_attribute(module, :server_action)

    if sact_attr do
      typescript_fallback_type_attr = get_attr(sact_attr, :typescript_fallback_type)

      typescript_fallback_type =
        if typescript_fallback_type_attr do
          Helpers.get_typescript_fallback_type(typescript_fallback_type_attr)
        end

      if Map.get(Module.get_attribute(module, :__live_server_actions, %{}), name) do
        raise Helpers.make_duplicate_live_action_definition_error(module, name)
      end

      Module.put_attribute(
        module,
        :__live_server_actions,
        Map.put(
          Module.get_attribute(module, :__live_server_actions, %{}),
          name,
          {length(args), typescript_fallback_type, kind}
        )
      )

      Module.delete_attribute(module, :server_action)
    end
  end

  def __on_definition__(_, _, _, _, _, _), do: nil

  defmacro __after_compile__(_env, bytecode) do
    quote do
      if Mix.env() == :dev do
        # TODO hack
        assets_dir =
          Path.join(Mix.Project.build_path() |> Path.dirname() |> Path.dirname(), "assets")

        Helpers.output_ts_definitions(
          __MODULE__,
          @__live_server_actions,
          unquote(bytecode),
          assets_dir,
          @__live_server_actions_typescript_fallback_type
        )
      end
    end
  end

  defmacro __before_compile__(%{module: module}) do
    live_server_actions = Module.get_attribute(module, :__live_server_actions)

    quote do
      # For each server action that's a private function, add a clause for
      # __live_server_actions_call_private_server_action(func_name, args_list).
      # This function can then be called from handle_event to dispatch private
      # server actions.
      unquote(
        live_server_actions
        |> Enum.filter(fn {_, {_, _, kind}} -> kind == :defp end)
        |> Enum.map(fn {name, {arity, _, _}} ->
          quote do
            defp __live_server_actions_call_private_server_action(unquote(name), args) do
              apply(
                # conceptually, the following is
                #   &unquote(name)/unquote(arity)
                unquote({:&, [], [{:/, [], [{name, [], module}, arity]}]}),
                args
              )
            end
          end
        end)
      )

      def handle_event(
            "live-server-action",
            params = %{"module_and_func" => module_and_func, "args" => args},
            socket
          ) do
        Helpers.handle_event(
          __MODULE__,
          @__live_server_actions,
          module_and_func,
          args,
          params["specials"] || Enum.map(args, fn _ -> [] end),
          socket,
          &__live_server_actions_call_private_server_action/2
        )
      end
    end
  end

  defp get_attr(lst = [_ | _], attr), do: lst[attr]
  defp get_attr(mp = %{}, attr), do: mp[attr]
  defp get_attr(_, _), do: nil
end
