defmodule LiveServerActions.Helpers do
  @moduledoc false

  require Logger
  alias LiveServerActions.Helpers.Unicode

  def handle_event(
        current_module,
        live_server_actions,
        module_and_func,
        args,
        specials,
        socket,
        call_private_live_server_action,
        opts \\ []
      ) do
    # allow this to be overridden in tests
    get_function_arg_and_ret_types =
      opts[:get_function_arg_and_ret_types] || (&get_function_arg_and_ret_types/3)

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

      {server_action_arguments, _typescript_fallback_type, kind} ->
        arity = length(server_action_arguments)

        # + 1 to allow for socket arg
        if length(args) + 1 != arity do
          raise "Wrong number of arguments for server action #{function}"
        end

        args = deserialize_specials(args, specials)

        args =
          case get_function_arg_and_ret_types.(current_module, function, arity) do
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

          {result, specials} = get_serialization_specials(result)

          if specials != [] do
            {:reply, %{result: result, specials: specials}, socket}
          else
            {:reply, %{result: result}, socket}
          end
        rescue
          e ->
            Logger.error(
              "Server action #{function} failed: #{Exception.format(:error, e, __STACKTRACE__)}"
            )

            # Let the client know that the server action failed. Don't send
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

  # Ditto
  def make_duplicate_live_action_definition_error(module_name, function_name) do
    """
    LiveServerActions assumes that server action names are unique within a
    module. The server action '#{function_name}' is defined multiple times in
    the module '#{module_name}'. Even if both definitions have the same arity,
    LiveServerActions does not support this because it leads to complications
    with type specs.
    """
  end

  # Ditto
  def make_empty_args_error(module_name, function_name) do
    """
    A server action must have at least one argument (the socket). The server
    action '#{function_name}' in the module '#{module_name}' has no arguments.
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
        tsdefs_filename,
        typescript_global_fallback_type,
        opts \\ []
      ) do
    write! = opts[:write!] || (&File.write!/2)

    modlist = Module.split(module)

    ts =
      server_actions
      |> Enum.map(fn {name, {arguments, typescript_fallback_type, _kind}} ->
        arity = length(arguments)

        [_ | argument_names] = get_argument_names(arguments)

        typescript_fallback_type =
          typescript_fallback_type ||
            get_typescript_fallback_type(typescript_global_fallback_type)

        spec = get_function_spec(module_or_bytecode, name, arity)

        if not valid_js_identifier?(name) do
          raise "Function name #{inspect(name)} is not a valid JS identifier"
        end

        case spec do
          nil ->
            "#{name}: (#{argument_names |> Enum.with_index() |> Enum.map(fn {name, i} -> "#{valid_js_identifier_or_nil(name) || "_#{i + 1}"}: #{typescript_fallback_type}" end) |> Enum.join(", ")}) => Promise<#{typescript_fallback_type}>"

          _ ->
            "#{name}: #{function_type_spec_to_ts_type(module, name, spec, argument_names, typescript_fallback_type)}"
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
      tsdefs_filename,
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
      deserialize_special(arg, specials)
    end)
  end

  defp deserialize_special(val, nil), do: val

  defp deserialize_special(val, specials = %{"type" => type}) do
    path = specials["path"]

    {list?, val} =
      case type do
        "id" ->
          # If we have a list, convert it to a map with integer keys. This makes
          # lists of specials (e.g. dates) deserialize in O(n log(n)) time rather
          # than O(n^2) time.
          list_to_map(val)

        "shadow_id" ->
          # A shadow is never a list, so no need to call list_to_map.
          {false, upd_at(val, path, fn _ -> specials["shadow"] end)}

        "Date" ->
          {false,
           upd_at(val, path, fn val ->
             {:ok, d, _} = DateTime.from_iso8601(val)
             d
           end)}

        "Set" ->
          {false, upd_at(val, path, fn _ -> MapSet.new(specials["shadow"]) end)}
      end

    val =
      Enum.reduce(specials["subs"] || [], val, fn sub, val ->
        upd_at(val, path, fn val -> deserialize_special(val, sub) end)
      end)

    if list? do
      Enum.map(val, fn {_, v} -> v end)
    else
      val
    end
  end

  def get_serialization_specials(val) do
    val
    |> get_serialization_specials_helper(nil)
    |> case do
      {val, specials} ->
        {val, List.first(specials)}
    end
  end

  defp get_serialization_specials_helper(val, path) do
    case val do
      %DateTime{} ->
        {val, mk_specials("Date", path, [])}

      %Date{} ->
        {val, mk_specials("Date", path, [])}

      [] ->
        {val, []}

      [_ | _] ->
        {new_vals, subs} =
          val
          |> Enum.with_index()
          |> Enum.reduce({[], []}, fn {v, i}, {new_vals, s} ->
            {vv, ss} = get_serialization_specials_helper(v, i)
            {[vv | new_vals], s ++ ss}
          end)

        {Enum.reverse(new_vals), mk_specials("id", path, subs)}

      %MapSet{} ->
        # We don't look inside sets for the reasons explained in the Readme.
        {MapSet.to_list(val), mk_specials("Set", path, [])}

      %{} ->
        {new_map, subs} =
          val
          |> Enum.reduce({val, []}, fn {k, v}, {new_map, s} ->
            {vv, ss} = get_serialization_specials_helper(v, k)
            {Map.put(new_map, k, vv), s ++ ss}
          end)

        {new_map, mk_specials("id", path, subs)}

      _ ->
        {val, []}
    end
  end

  defp list_to_map(val) when is_list(val) do
    {true,
     val
     |> Enum.reduce({0, %{}}, fn v, {i, m} ->
       {i + 1, Map.put(m, i, v)}
     end)
     |> elem(1)}
  end

  defp list_to_map(val) do
    {false, val}
  end

  defp mk_specials(type, path, subs) do
    if type == "id" and subs == [] do
      []
    else
      [type: type]
      |> Enum.concat(if path != nil, do: [path: path], else: [])
      |> Enum.concat(if subs != [], do: [subs: subs], else: [])
      |> Map.new()
      |> List.wrap()
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

  defp function_type_spec_to_ts_type(
         module,
         sa_name,
         spec,
         argument_names,
         typescript_fallback_type
       ) do
    case spec do
      {:type, _, :fun, [{:type, _, :product, [_socket_type | arg_types]}, return_type]} ->
        # We don't check that socket_type is Phoenix.LiveView.Socket because
        # lazy programmers might want to just type the first arg as any().

        ret =
          type_to_ts_type(
            strip_socket_tuple_from_return_type(return_type),
            typescript_fallback_type
          )

        if length(arg_types) != length(argument_names) do
          raise "Wrong number of arguments in type spec for server action #{sa_name} in module #{module}"
        end

        args =
          arg_types
          |> Enum.with_index()
          |> Enum.zip(argument_names)
          |> Enum.map(fn {{arg_type, i}, name} ->
            "#{valid_js_identifier_or_nil(name) || "_#{i + 1}"}: " <>
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

  defp upd_at(value, nil, f), do: f.(value)

  defp upd_at(value = [_ | _], idx, f) do
    # Note: List.update_at does nothing if the index is out of range.
    List.update_at(value, idx, f)
  end

  defp upd_at(value = %{}, key, f) do
    map_upd_if_exists(value, key, f)
  end

  defp upd_at(value, _path, _f), do: value

  defp map_upd_if_exists(map, key, f) do
    if Map.has_key?(map, key) do
      Map.update!(map, key, f)
    else
      map
    end
  end

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

  defp valid_js_identifier_or_nil(identifier) do
    if valid_js_identifier?(identifier) do
      identifier
    else
      nil
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

  defp get_argument_names(arguments) do
    Enum.map(arguments, fn arg ->
      arg
      |> case do
        {name, _linecol, nil} when is_atom(name) ->
          name

        {:=, _linecol1,
         [
           {name, _linecol2, nil},
           _
         ]}
        when is_atom(name) ->
          name

        {:=, _linecol1,
         [
           _,
           {name, _linecol2, nil}
         ]}
        when is_atom(name) ->
          name

        _ ->
          nil
      end
      |> case do
        nil ->
          nil

        name ->
          String.replace_prefix("#{name}", "_", "")
      end
    end)
  end
end
