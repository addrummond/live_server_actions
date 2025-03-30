defmodule LiveServerActions.HelpersTest do
  use ExUnit.Case

  alias LiveServerActions.Helpers
  alias LiveServerActions.TestSupport.{MyServact, TypeData}

  # see LiveServerActions.HelpersTest.Typedata module
  @type_to_ts_type_expectations [
    {:t_string_string_t, 0, [], "string"},
    {:t_string_binary, 0, [], "string"},
    {:t_boolean, 0, [], "boolean"},
    {:t_true, 0, [], "true"},
    {:t_false, 0, [], "false"},
    {:t_nil, 0, [], "null"},
    {:t_intconst, 0, [], "number"},
    {:t_intrange, 0, [], "number"},
    {:t_float, 0, [], "number"},
    {:t_integer, 0, [], "number"},
    {:t_pos_integer, 0, [], "number"},
    {:t_neg_integer, 0, [], "number"},
    {:t_non_neg_integer, 0, [], "number"},
    {:t_non_neg_integer, 0, [], "number"},
    {:t_map_any, 0, [], "object"},
    {:t_none1, 0, [], "undefined"},
    {:t_none2, 0, [], "undefined"},
    {:t_module, 0, [], "string"},
    {:t_node, 0, [], "string"},
    {:t_complex_example1, 2, ["number", "({key1: object} | {key2: number})"], "(number | object)"}
  ]

  describe "type_to_ts_type/2" do
    test "table" do
      for {type, arity, expected_args, expected_ret} <- @type_to_ts_type_expectations do
        {actual_args, actual_ret} =
          Helpers.get_function_arg_and_ret_types(TypeData, type, arity)

        assert LiveServerActions.Helpers.type_to_ts_type(actual_ret, :any) == expected_ret

        assert Enum.map(actual_args, &LiveServerActions.Helpers.type_to_ts_type(&1, :any)) ==
                 expected_args
      end
    end
  end

  describe "deserialize_specials/2" do
    test "no args, no specials" do
      assert Helpers.deserialize_specials([], []) == []
    end

    test "a complicated case" do
      args = [
        "2025-03-18T19:13:34.026831Z",
        ["bar", "2027-03-18T19:13:34.026831Z"],
        %{"foo" => ["bar", %{"amp" => "2026-03-18T19:13:34.026831Z"}]}
      ]

      specials = [
        [%{"type" => "Date", "path" => []}],
        [%{"type" => "Date", "path" => [1]}],
        [%{"type" => "Date", "path" => ["foo", 1, "amp"]}]
      ]

      assert Helpers.deserialize_specials(args, specials) == [
               ~U[2025-03-18 19:13:34.026831Z],
               ["bar", ~U[2027-03-18 19:13:34.026831Z]],
               %{"foo" => ["bar", %{"amp" => ~U[2026-03-18 19:13:34.026831Z]}]}
             ]
    end
  end

  describe "get_serialization_specials/3" do
    test "no args, no specials" do
      assert Helpers.get_serialization_specials([], [], []) == []
    end

    test "a complicated case" do
      val = [
        ~U[2025-03-18 19:13:34.026831Z],
        ["bar", ~U[2027-03-18 19:13:34.026831Z]],
        %{"foo" => ["bar", %{"amp" => ~U[2026-03-18 19:13:34.026831Z]}]}
      ]

      expected_specials = [
        %{type: "Date", path: [0]},
        %{type: "Date", path: [1, 1]},
        %{type: "Date", path: [2, "foo", 1, "amp"]}
      ]

      assert Helpers.get_serialization_specials(val) == expected_specials
    end
  end

  @expected_ts_defs_output """
  declare module "live_server_actions" {
    namespace ServerActions.LiveServerActions {
      interface TestSupport {
        MyServact: ServerActions.LiveServerActions.TestSupport.MyServact;
      }
    }
    
    namespace ServerActions.LiveServerActions.TestSupport {
      interface MyServact {
        pub_no_typespec: (any, any) => Promise<any>
        priv_no_typespec: (any, any) => Promise<any>
        pub_with_typespec: ({fruit: string, another_key: {foo: number, bar: string}}) => Promise<({error: string} | {quote: string, author: string, year: number})>
        priv_with_typespec: ({fruit: string}) => Promise<({error: string} | {quote: string, author: string, year: number})>
        _日本語識別子: (any) => Promise<any>
      }
    }
    
    namespace ServerActions {
      interface LiveServerActions {
        TestSupport: ServerActions.LiveServerActions.TestSupport;
      }
    }
    interface ServerActions {
      LiveServerActions: ServerActions.LiveServerActions;
    }
  }
  """

  describe "output_ts_definitions/6" do
    test "no typespecs" do
      # In the real code the third arg would be the bytecode as we wouldn't be
      # able to look up things via the module name at this stage.
      {fname, contents} =
        Helpers.output_ts_definitions(
          MyServact,
          [
            {:pub_no_typespec, {3, :any, :def}},
            {:priv_no_typespec, {3, :any, :defp}},
            {:pub_with_typespec, {2, :any, :def}},
            {:priv_with_typespec, {2, :any, :defp}},
            {:_日本語識別子, {2, :any, :def}}
          ],
          MyServact,
          "assets",
          :any,
          write!: fn name, content -> {name, content} end
        )

      assert {"assets/js/LiveServerActions__Elixir.LiveServerActions.TestSupport.MyServact.d.ts",
              String.trim(@expected_ts_defs_output)} == {fname, String.trim(contents)}
    end
  end

  describe "handle_event/7" do
    test "a simple public server action returns the expected value" do
      defmodule MyServact1 do
        def a_server_action(_socket, _arg1) do
          "return value"
        end
      end

      assert {:reply, %{result: "return value"}, %Phoenix.LiveView.Socket{}} =
               Helpers.handle_event(
                 MyServact1,
                 %{
                   a_server_action: {2, :any, :def}
                 },
                 ["LiveServerActions.HelpersTest.MyServact1", "a_server_action"],
                 ["arg1"],
                 [[]],
                 %Phoenix.LiveView.Socket{},
                 fn _ -> raise "should not be called" end,
                 get_function_arg_and_ret_types: fn _, _, _ -> nil end
               )
    end

    test "a simple private server action returns the expected value" do
      defmodule MyServact2 do
        # No implementation here because we can't call a private function in
        # this module from test code outside the module. Instead we just fake
        # it in the implementation of call_private_live_server_action given to
        # handle_event.
      end

      assert {:reply, %{result: "return value"}, %Phoenix.LiveView.Socket{}} =
               Helpers.handle_event(
                 MyServact2,
                 %{
                   a_server_action: {2, :any, :defp}
                 },
                 ["LiveServerActions.HelpersTest.MyServact2", "a_server_action"],
                 ["arg1"],
                 [[]],
                 %Phoenix.LiveView.Socket{},
                 fn :a_server_action, _args ->
                   # In reality, this would be a call to
                   # __live_server_actions_call_private_server_action
                   "return value"
                 end,
                 get_function_arg_and_ret_types: fn _, _, _ -> nil end
               )
    end

    test "handles {socket, x} return values by stripping socket and passing it through to {:reply, ...} tuple" do
      defmodule MyServact3 do
        def a_server_action(socket, _arg1) do
          {%{socket | assigns: %{my: "assigns"}}, "return value"}
        end
      end

      assert {:reply, %{result: "return value"},
              %Phoenix.LiveView.Socket{assigns: %{my: "assigns"}}} =
               Helpers.handle_event(
                 MyServact3,
                 %{
                   a_server_action: {2, :any, :def}
                 },
                 ["LiveServerActions.HelpersTest.MyServact3", "a_server_action"],
                 ["arg1"],
                 [[]],
                 %Phoenix.LiveView.Socket{},
                 fn _ -> raise "should not be called" end,
                 get_function_arg_and_ret_types: fn _, _, _ -> nil end
               )
    end

    test "correctly deserializes a date argument" do
      defmodule MyServact4 do
        def a_server_action(_socket, some_date) do
          some_date
        end
      end

      assert {:reply, %{result: ~U[2025-03-18 19:13:34.026831Z]}, %Phoenix.LiveView.Socket{}} =
               Helpers.handle_event(
                 MyServact4,
                 %{
                   a_server_action: {2, :any, :def}
                 },
                 ["LiveServerActions.HelpersTest.MyServact4", "a_server_action"],
                 ["2025-03-18T19:13:34.026831Z"],
                 [[%{"type" => "Date", "path" => []}]],
                 %Phoenix.LiveView.Socket{},
                 fn _ -> raise "should not be called" end,
                 get_function_arg_and_ret_types: fn _, _, _ -> nil end
               )
    end

    test "correctly deserializes a date argument and a nested date value" do
      defmodule MyServact5 do
        def a_server_action(_socket, some_date, %{"dates" => [date]}) do
          [some_date, date]
        end
      end

      assert {:reply,
              %{result: [~U[2025-03-18 19:13:34.026831Z], ~U[2023-03-18 19:13:34.026831Z]]},
              %Phoenix.LiveView.Socket{}} =
               Helpers.handle_event(
                 MyServact5,
                 %{
                   a_server_action: {3, :any, :def}
                 },
                 ["LiveServerActions.HelpersTest.MyServact5", "a_server_action"],
                 ["2025-03-18T19:13:34.026831Z", %{"dates" => ["2023-03-18T19:13:34.026831Z"]}],
                 [
                   [%{"type" => "Date", "path" => []}],
                   [%{"type" => "Date", "path" => ["dates", 0]}]
                 ],
                 %Phoenix.LiveView.Socket{},
                 fn _ -> raise "should not be called" end,
                 get_function_arg_and_ret_types: fn _, _, _ -> nil end
               )
    end

    test "raises error if server action is of a different module" do
      defmodule MyServact6 do
        def a_server_action(_socket, _arg1) do
          "return value"
        end
      end

      defmodule MyServact7 do
        def a_different_server_action(_socket, _arg1) do
          "return value"
        end
      end

      assert_raise RuntimeError, "Wrong module for server action", fn ->
        Helpers.handle_event(
          MyServact6,
          %{
            a_server_action: {2, :any, :def}
          },
          ["LiveServerActions.HelpersTest.MyServact7", "a_server_action"],
          ["arg1"],
          [[]],
          %Phoenix.LiveView.Socket{},
          fn _ -> raise "should not be called" end,
          get_function_arg_and_ret_types: fn _, _, _ -> nil end
        )
      end
    end

    test "raises error if server action is given wrong number of args" do
      defmodule MyServact8 do
        def a_server_action(_socket, _arg1) do
          "return value"
        end
      end

      assert_raise RuntimeError,
                   "Wrong number of arguments for server action a_server_action",
                   fn ->
                     Helpers.handle_event(
                       MyServact8,
                       %{
                         a_server_action: {2, :any, :def}
                       },
                       ["LiveServerActions.HelpersTest.MyServact8", "a_server_action"],
                       ["arg1", "arg2"],
                       [[]],
                       %Phoenix.LiveView.Socket{},
                       fn _ -> raise "should not be called" end,
                       get_function_arg_and_ret_types: fn _, _, _ -> nil end
                     )
                   end
    end
  end
end
