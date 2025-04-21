defmodule LiveServerActions.E2E.SerializationTest do
  use ExUnit.Case

  alias LiveServerActions.Helpers

  describe "elixir to javascript" do
    test "a trivial case (null)" do
      test_elixir_to_javascript(nil, "null")
    end

    test "a trivial case (99)" do
      test_elixir_to_javascript(99, "99")
    end

    test "a top level date" do
      test_elixir_to_javascript(
        ~U[2023-10-01 00:00:00.000Z],
        "new Date('2023-10-01T00:00:00.000Z')"
      )
    end

    test "a complex value with no specials" do
      test_elixir_to_javascript([[[%{"foo" => "bar"}]]], "[[[{foo: \"bar\"}]]]")
    end

    test "a complex value with specials" do
      test_elixir_to_javascript(
        %{
          foo: "bar",
          amp: [
            MapSet.new([1, 2, 3]),
            %{
              99 => 100,
              "bar" => MapSet.new(["foo", "bar", "amp"]),
              "date" => ~U[2023-10-01 00:00:00.000Z]
            }
          ]
        },
        """
        { foo: 'bar',
          amp: [
            new Set([1, 2, 3]),
            {
              '99': 100,
              bar: new Set(['amp', 'bar', 'foo']),
              date: new Date('2023-10-01T00:00:00.000Z')
            }
          ]
        }
        """
      )
    end
  end

  describe "javascript to elixir" do
    test "a trivial case (null)" do
      test_javascript_to_elixir("null", nil)
    end

    test "a trivial case (99)" do
      test_javascript_to_elixir("99", 99)
    end

    test "a top level date" do
      test_javascript_to_elixir(
        "new Date('2023-10-01T00:00:00.000Z')",
        ~U[2023-10-01 00:00:00.000Z]
      )
    end

    test "a complex value with no specials" do
      test_javascript_to_elixir("[[[{foo: \"bar\"}]]]", [[[%{"foo" => "bar"}]]])
    end

    test "a complex value with specials" do
      test_javascript_to_elixir(
        """
        {
          foo: 'bar',
          date: new Date('2023-10-01T00:00:00Z'),
          date_in_map: new Map([["date", new Date('2020-10-01T00:00:00Z')]]),
          amp: [
            new Set([1, 2, 3]),
            { '99': 100, bar: new Set(['amp', 'bar', 'foo']) }
          ]
        }
        """,
        %{
          "foo" => "bar",
          "date" => ~U[2023-10-01 00:00:00.000Z],
          "date_in_map" => %{
            "date" => ~U[2020-10-01 00:00:00.000Z]
          },
          "amp" => [
            MapSet.new([1, 2, 3]),
            %{"99" => 100, "bar" => MapSet.new(["amp", "bar", "foo"])}
          ]
        }
      )
    end
  end

  defp test_elixir_to_javascript(elixir_value, expected_js_value) do
    {val, specials} = Helpers.get_serialization_specials(elixir_value)
    val_json = JSON.encode!(val)
    specials_json = JSON.encode!(specials)

    {_, exit_code} =
      System.cmd(
        "node",
        [
          "-e",
          """
          import { deserializeSpecials } from "./assets/serialize.js";
          import { inspect } from "util";
          import { deepEqual } from "assert";
          const input = process.env.LIVE_SERVER_ACTIONS_TEST_JSON;
          const result = deserializeSpecials(
            JSON.parse(process.env.LIVE_SERVER_ACTIONS_TEST_VAL_JSON),
            JSON.parse(process.env.LIVE_SERVER_ACTIONS_TEST_SPECIALS_JSON)
          );
          const expected = (#{expected_js_value});
          deepEqual(result, expected);
          """
        ],
        env: %{
          "LIVE_SERVER_ACTIONS_TEST_VAL_JSON" => val_json,
          "LIVE_SERVER_ACTIONS_TEST_SPECIALS_JSON" => specials_json
        }
      )

    assert exit_code == 0
  end

  defp test_javascript_to_elixir(js_input_value, expected_elixir_value) do
    {out, exit_code} =
      System.cmd(
        "node",
        [
          "-e",
          """
          import { getSerializationSpecials } from "./assets/serialize.js";
          const input = (#{js_input_value});
          const specials = getSerializationSpecials(input);
          console.log(JSON.stringify({specials, input}));
          """
        ],
        into: ""
      )

    assert exit_code == 0

    %{"input" => input, "specials" => specials} = JSON.decode!(out)

    [deserialized] = Helpers.deserialize_specials([input], [specials])

    assert deserialized == expected_elixir_value
  end
end
