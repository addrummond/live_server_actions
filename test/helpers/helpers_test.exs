defmodule LiveServerActions.HelpersTest do
  use ExUnit.Case

  alias LiveServerActions.Helpers

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
          Helpers.get_function_arg_and_ret_types(LiveServerActions.TestData.TypeData, type, arity)

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

  # TODO: Test coverage could be, err, a little more comprehensive.
end
