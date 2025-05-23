defmodule LiveServerActions do
  @moduledoc """
  Add `use LiveServerActions` to your module to enable server actions.

  Server actions may be public or private functions, and must have the attribute
  `@server_action true`.

  See readme at https://github.com/addrummond/live_server_actions/tree/main for
  more information.
  """

  @tsdefs_prefix "LiveServerActions__"

  alias LiveServerActions.Helpers

  @doc false
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

      @__live_server_actions_d_ts_output_dir unquote(args[:d_ts_output_dir])
      @__live_server_actions_get_d_ts_filename unquote(args[:get_d_ts_filename])

      # make sure this is defined at least once with a guard that won't match
      # anything
      defp __live_server_actions_call_private_server_action(nil, nil), do: nil
    end
  end

  @doc false
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

      if args == [] do
        raise Helpers.make_empty_args_error(module, name)
      end

      Module.put_attribute(
        module,
        :__live_server_actions,
        Map.put(
          Module.get_attribute(module, :__live_server_actions, %{}),
          name,
          {args, typescript_fallback_type, kind}
        )
      )

      Module.delete_attribute(module, :server_action)
    end
  end

  @doc false
  def __on_definition__(_, _, _, _, _, _), do: nil

  @doc false
  defmacro __after_compile__(_env, bytecode) do
    quote do
      if Mix.env() == :dev do
        # TODO hack
        project_dir = Mix.Project.build_path() |> Path.dirname() |> Path.dirname()

        default_d_ts_output_dir =
          Path.join([project_dir, "assets", "js"])

        d_ts_output_dir_option = @__live_server_actions_d_ts_output_dir

        d_ts_output_dir =
          cond do
            is_function(d_ts_output_dir_option, 1) ->
              "" <> d_ts_output_dir_option.(project_dir)

            is_binary(d_ts_output_dir_option) ->
              d_ts_output_dir_option

            d_ts_output_dir_option == false ->
              false

            d_ts_output_dir_option == nil ->
              default_d_ts_output_dir
          end

        if d_ts_output_dir != false do
          get_d_ts_filename_option = @__live_server_actions_get_d_ts_filename

          get_d_ts_filename =
            get_d_ts_filename_option ||
              fn output_dir, module_name ->
                Path.join([output_dir, "#{unquote(@tsdefs_prefix)}#{module_name}.d.ts"])
              end

          d_ts_filename =
            get_d_ts_filename.(d_ts_output_dir, Enum.join(Module.split(__MODULE__), "."))

          Helpers.output_ts_definitions(
            __MODULE__,
            @__live_server_actions,
            unquote(bytecode),
            d_ts_filename,
            @__live_server_actions_typescript_fallback_type
          )
        end
      end
    end
  end

  @doc false
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
        |> Enum.map(fn {name, {server_action_arguments, _, _}} ->
          arity = length(server_action_arguments)

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
          params["specials"] || Enum.map(args, fn _ -> nil end),
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
