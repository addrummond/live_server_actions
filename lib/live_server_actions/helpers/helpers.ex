defmodule LiveServerActions.Helpers do
  require Logger
  alias LiveServerActions.Helpers.Unicode

  @tsdefs_prefix "LiveServerActions__"

  def handle_event(
        current_module,
        live_server_actions,
        module_and_func,
        args,
        specials,
        socket,
        call_private_live_server_action
      ) do
    module = module_and_func |> Enum.drop(-1) |> Enum.join(".")

    if "Elixir.#{module}" != "#{current_module}" do
      raise "Wrong module for server action"
    end

    fname = List.last(module_and_func)

    function =
      try do
        String.to_existing_atom(fname)
      rescue
        _ ->
          nil
      end

    case live_server_actions[function] do
      nil ->
        raise "No server action #{fname} defined in #{current_module}"

      {arity, _typescript_fallback_type, kind} ->
        # + 1 to allow for socket arg
        if length(args) + 1 != arity do
          raise "Wrong number of arguments for server action #{function}"
        end

        args = deserialize_specials(args, specials)

        args =
          case get_function_arg_and_ret_types(current_module, function, arity) do
            {[_socket | arg_types], _} ->
              Enum.map(Enum.zip(args, arg_types), fn {arg, arg_type} ->
                mung(arg, arg_type)
              end)

            nil ->
              # There was no type spec, so we take the args as-is without
              # munging.
              args
          end

        try do
          result =
            if kind == :defp do
              call_private_live_server_action.(function, [socket | args])
            else
              apply(current_module, function, [socket | args])
            end

          # If the function returns a {socket, result} tuple, thread the new
          # value of the socket into {:reply, ...}
          {socket, result} =
            case result do
              {socket = %Phoenix.LiveView.Socket{}, result} ->
                {socket, result}

              _ ->
                {socket, result}
            end

          {:reply, add_retval_specials(%{result: result}, result), socket}
        rescue
          e ->
            Logger.error(
              "Server action #{function} failed: #{Exception.format(:error, e, __STACKTRACE__)}"
            )

            # Let the client know that the server action failed. Don't sent
            # error value or stacktrace to client in case they contain sensitive
            # information.
            {:reply,
             %{
               error: "Server action #{function} failed"
             }, socket}
        end
    end
  end

  def get_function_arg_and_ret_types(module_or_bytecode, function, arity) do
    case get_cached_function_spec(module_or_bytecode, function, arity) do
      nil ->
        nil

      {:type, _, :fun, [{:type, _, :product, arg_types}, return_type]} ->
        {arg_types, return_type}
    end
  end

  def type_to_ts_type(spec, typescript_fallback_type) do
    case spec do
      {:remote_type, _, [{:atom, _, String}, {:atom, _, :t}, []]} ->
        "string"

      {:type, _, :binary, []} ->
        "string"

      {:type, _, :nonempty_binary, []} ->
        "string"

      {:type, _, :float, []} ->
        "number"

      {:type, _, int, []}
      when int in [:integer, :pos_integer, :neg_integer, :non_neg_integer] ->
        "number"

      {:type, _, :map, :any} ->
        "object"

      {:type, _, :map, []} ->
        "object"

      {:type, _, :any, []} ->
        "any"

      {:type, _, :none, []} ->
        "undefined"

      {:type, _, :no_return, []} ->
        "undefined"

      {:type, _, :module, []} ->
        "string"

      {:type, _, :node, []} ->
        "string"

      {:type, _, :boolean, []} ->
        "boolean"

      {:atom, _, true} ->
        "true"

      {:atom, _, false} ->
        "false"

      {:atom, _, nil} ->
        "null"

      {:integer, _, _} ->
        "number"

      {:type, _, :range, [{:integer, _, _}, {:integer, _, _}]} ->
        "number"

      {:type, _, :map, [_ | _] = keys} ->
        "{" <>
          (Enum.map(keys, fn key ->
             case key do
               {:type, _, :map_field_exact, [{:atom, _, key}, t]} ->
                 if not valid_js_identifier?(key) do
                   # TODO generate quoted key in TS defs instead of raising
                   raise "Key #{inspect(key)} is not a valid JS identifier"
                 end

                 "#{key}: #{type_to_ts_type(t, typescript_fallback_type)}"

               {:type, _, :map_field_assoc, [{:atom, _, key}, t]} ->
                 if not valid_js_identifier?(key) do
                   # TODO generate quoted key in TS defs instead of raising
                   raise "Key #{inspect(key)} is not a valid JS identifier"
                 end

                 "#{key}?: #{type_to_ts_type(t, typescript_fallback_type)}"

               _ ->
                 typescript_fallback_type
             end
           end)
           |> Enum.join(", ")) <> "}"

      {:type, _, nil, []} ->
        # Empty array
        "never[]"

      {:type, _, :list, [type]} ->
        "(#{type_to_ts_type(type, typescript_fallback_type)})[]"

      {:type, _, :nonempty_list, [type]} ->
        rt = type_to_ts_type(type, typescript_fallback_type)
        "[(#{rt}), ...(#{rt})[]]"

      {:type, _, :union, ts} ->
        "(" <>
          Enum.join(Enum.map(ts, fn t -> type_to_ts_type(t, typescript_fallback_type) end), " | ") <>
          ")"

      _ ->
        if Mix.env() == :test do
          IO.inspect(spec, label: "UNSUPPORTED TYPE")
        end

        "#{typescript_fallback_type}"
    end
  end

  # Avoids having this string constant duplicated in macro generated code
  def make_module_name_double_underscore_error(module_name) do
    """
    LiveServerActions assumes that Elixir module names do not contain double
    underscores ('__'). This is because it uses double underscores as part
    of its name mangling strategy for the Typescript '.d.ts' files that it
    outputs.

    The module name '#{module_name}' does not meet this requirement.
    """
  end

  def get_typescript_fallback_type(:any), do: "any"
  def get_typescript_fallback_type(:unknown), do: "unknown"

  def get_typescript_fallback_type(d),
    do: raise(":typescript_fallback_type must be :any or :unknown, got #{inspect(d)}")

  def output_ts_definitions(
        module,
        server_actions,
        module_or_bytecode,
        assets_dir,
        typescript_global_fallback_type,
        opts \\ []
      ) do
    write! = opts[:write!] || (&File.write!/2)

    # TODO should be customizable
    tsdefs_dir = Path.join(assets_dir, "js")

    modlist = Module.split(module)

    ts =
      server_actions
      |> Enum.map(fn {name, {arity, typescript_fallback_type, _kind}} ->
        typescript_fallback_type =
          typescript_fallback_type ||
            get_typescript_fallback_type(typescript_global_fallback_type)

        spec = get_function_spec(module_or_bytecode, name, arity)

        if not valid_js_identifier?(name) do
          raise "Function name #{inspect(name)} is not a valid JS identifier"
        end

        case spec do
          nil ->
            "#{name}: (#{1..(arity - 1) |> Enum.map(fn _ -> "#{typescript_fallback_type}" end) |> Enum.join(", ")}) => Promise<#{typescript_fallback_type}>"

          _ ->
            "#{name}: #{function_type_spec_to_ts_type(spec, typescript_fallback_type)}"
        end
      end)
      |> Enum.join("\n")

    if not Enum.all?(modlist, &valid_js_identifier?/1) do
      raise "The module #{Enum.join(modlist, ".")} is not a sequence of valid JS identifiers"
    end

    tsdef =
      """
      #{initial_def(modlist)}

      namespace ServerActions#{right_join_module(Enum.join(module_prefix(modlist), "."))} {
        interface #{module_terminal(modlist)} {
          #{indent(4, ts)}
        }
      }
      """

    # Stubs for potential parent modules, required if these modules don't
    # exist or exist but don't contain server action definitions.
    stub = fn modlist, stub ->
      if modlist != [] do
        [Enum.join([initial_def(modlist)] ++ stub.(Enum.drop(modlist, -1), stub), "\n")]
      else
        []
      end
    end

    stubs = stub.(Enum.drop(modlist, -1), stub) |> List.first() || ""

    # The following is already declared in the .d.ts file for the npm module
    #
    #   export const serverActions : ServerActions;
    #   interface ServerActions { }

    write!.(
      Path.join(tsdefs_dir, "#{@tsdefs_prefix}#{module}.d.ts"),
      """
      declare module "live_server_actions" {
        #{indent(2, tsdef)}
        #{indent(2, stubs)}
      }
      """
    )
  end

  def deserialize_specials(args, specials) do
    Enum.map(Enum.zip(args, specials), fn {arg, specials} ->
      Enum.reduce(specials, arg, fn %{"type" => type, "path" => path}, arg ->
        upd_at(arg, path, fn a ->
          case {a, type} do
            {"" <> _, "Date"} ->
              {:ok, d, _} = DateTime.from_iso8601(a)
              d

            _ ->
              raise "Unknown special type #{inspect(type)}"
          end
        end)
      end)
    end)
  end

  def get_serialization_specials(val, path \\ [], specials \\ []) do
    case val do
      %DateTime{} ->
        specials ++ [%{type: "Date", path: Enum.reverse(path)}]

      %Date{} ->
        specials ++ [%{type: "Date", path: Enum.reverse(path)}]

      [] ->
        specials

      [_ | _] ->
        val
        |> Enum.with_index()
        |> Enum.map(fn {v, i} ->
          get_serialization_specials(v, [i | path], specials)
        end)
        |> Enum.concat()

      %{} ->
        val
        |> Enum.map(fn {k, v} ->
          get_serialization_specials(v, [k | path], specials)
        end)
        |> Enum.concat()

      _ ->
        specials
    end
  end

  defp add_retval_specials(map, result) do
    specials = get_serialization_specials(result)

    if specials != [] do
      Map.put(map, :specials, specials)
    else
      map
    end
  end

  defp get_cached_function_spec(module, function, arity) when is_atom(module) do
    case :ets.lookup(:live_server_actions_type_spec_lookup, {module, function, arity}) do
      [{_, spec}] ->
        spec

      [] ->
        spec = get_function_spec(module, function, arity)
        :ets.insert(:live_server_actions_type_spec_lookup, {{module, function, arity}, spec})
        spec
    end
  end

  defp get_function_spec(module_or_bytecode, function, arity) do
    {:ok, specs} = Code.Typespec.fetch_specs(module_or_bytecode)

    specs
    |> Enum.find(fn spec ->
      case spec do
        {{^function, ^arity}, [_]} ->
          true

        _ ->
          false
      end
    end)
    |> case do
      nil ->
        nil

      {_, [spec = {:type, _, :fun, [{:type, _, :product, _}, _]}]} ->
        spec
    end
  end

  defp initial_def(modlist) do
    {ind, ns_and_int, closing} =
      module_prefix(modlist)
      |> case do
        nil ->
          {2, "interface ServerActions {", "}"}

        _ ->
          {4,
           "namespace ServerActions#{right_join_module((module_prefix2(modlist) || []) |> Enum.join("."))} {\n" <>
             "  interface #{module_penul(modlist)} {", "  }\n}"}
      end

    if not Enum.all?(modlist, &valid_js_identifier?/1) do
      raise "The module #{Enum.join(modlist, ".")} is not a sequence of valid JS identifiers"
    end

    """
    #{ns_and_int}
    #{String.duplicate(" ", ind)}#{module_terminal(modlist)}: ServerActions.#{Enum.join(modlist, ".")};
    #{closing}
    """
    |> String.trim_trailing("\n")
  end

  defp function_type_spec_to_ts_type(spec, typescript_fallback_type) do
    case spec do
      {:type, _, :fun, [{:type, _, :product, [_socket_type | arg_types]}, return_type]} ->
        # We don't check that socket_type is Phoenix.LiveView.Socket because
        # lazy programmers might want to just type the first arg as any().

        ret =
          type_to_ts_type(
            strip_socket_tuple_from_return_type(return_type),
            typescript_fallback_type
          )

        args =
          Enum.map(arg_types, fn arg_type ->
            type_to_ts_type(arg_type, typescript_fallback_type)
          end)

        "(#{Enum.join(args, ", ")}) => Promise<#{ret}>"

      _ ->
        if Mix.env() == :test do
          IO.inspect(spec, label: "UNSUPPORTED TYPE")
        end

        "#{typescript_fallback_type}"
    end
  end

  defp upd_at(value, [], f), do: f.(value)

  defp upd_at(value = [_ | _], [idx], f) do
    List.update_at(value, idx, f)
  end

  defp upd_at(value = [_ | _], [idx | rest], f) do
    List.update_at(value, idx, fn elem -> upd_at(elem, rest, f) end)
  end

  defp upd_at(value = %{}, [key], f) do
    Map.update!(value, key, f)
  end

  defp upd_at(value = %{}, [key | rest], f) do
    Map.update!(value, key, fn elem -> upd_at(elem, rest, f) end)
  end

  defp upd_at(value, _path, _f), do: value

  defp mung(arg = %{}, {:type, _, :map, field_types}) do
    Enum.reduce(field_types, arg, fn t, acc ->
      case t do
        {:type, _, map_field, [{:atom, _, key}, kt]}
        when map_field in [:map_field_exact, :map_field_assoc] ->
          if Map.has_key?(acc, "#{key}") do
            acc
            |> Map.put(key, mung(acc["#{key}"], kt))
            |> Map.delete("#{key}")
          else
            acc
          end

        _ ->
          arg
      end
    end)
  end

  defp mung(arg = [_ | _], {:type, _, :list, [t]}) do
    Enum.map(arg, fn a -> mung(a, t) end)
  end

  # We just successively mung the value according to the type of element of the
  # union. This feels weird but I think it works.
  defp mung(arg, {:type, _, :union, ts}) do
    Enum.reduce(ts, arg, fn t, arg ->
      mung(arg, t)
    end)
  end

  defp mung(arg, _type), do: arg

  defp module_prefix(modlist) do
    case modlist do
      [] -> nil
      [_] -> nil
      lst -> Enum.drop(lst, -1)
    end
  end

  defp module_prefix2(modlist) do
    case modlist do
      [] -> nil
      [_] -> nil
      [_, _] -> nil
      lst -> Enum.drop(lst, -2)
    end
  end

  defp module_penul(modlist) do
    case modlist do
      [] -> nil
      [_] -> nil
      lst -> Enum.at(lst, -2)
    end
  end

  defp module_terminal(modlist) do
    List.last(modlist)
  end

  defp right_join_module(nil), do: ""
  defp right_join_module(""), do: ""
  defp right_join_module(right), do: ".#{right}"

  defp indent(n, str) do
    String.split(str, "\n")
    |> case do
      [] ->
        ""

      [x] ->
        x

      [fst | rst] ->
        fst <>
          "\n" <>
          Enum.join(Enum.map(rst, fn line -> "#{String.duplicate(" ", n)}#{line}" end), "\n")
    end
  end

  defp valid_js_identifier?(identifier) do
    identifier = "#{identifier}"

    case String.to_charlist(identifier) do
      [] ->
        false

      [fst | rst] ->
        (fst in [?$, ?_] or Unicode.id_start?(fst)) and
          Enum.all?(rst, &(&1 in [?$, ?_] or Unicode.id_continue?(&1)))
    end
  end

  defp strip_socket_tuple_from_return_type(
         {:type, _, :tuple,
          [
            {:remote_type, _, [{:atom, _, Phoenix.LiveView.Socket}, {:atom, _, :t}, []]},
            t
          ]}
       ),
       do: t

  defp strip_socket_tuple_from_return_type(t), do: t
end
