defmodule LiveServerActions.TestSupport.TypeData do
  @spec t_string_string_t() :: String.t()
  def t_string_string_t(), do: nil

  @spec t_string_binary() :: binary()
  def t_string_binary(), do: nil

  @spec t_boolean() :: boolean()
  def t_boolean(), do: nil

  @spec t_true() :: true
  def t_true(), do: nil

  @spec t_false() :: false
  def t_false(), do: nil

  @spec t_nil() :: nil
  def t_nil(), do: nil

  @spec t_intconst() :: 1
  def t_intconst(), do: nil

  @spec t_intrange() :: 1..10
  def t_intrange(), do: nil

  @spec t_float() :: float()
  def t_float(), do: nil

  @spec t_integer() :: integer()
  def t_integer(), do: nil

  @spec t_pos_integer() :: pos_integer()
  def t_pos_integer(), do: nil

  @spec t_neg_integer() :: neg_integer()
  def t_neg_integer(), do: nil

  @spec t_non_neg_integer() :: non_neg_integer()
  def t_non_neg_integer(), do: nil

  @spec t_map_any() :: map()
  def t_map_any(), do: nil

  @spec t_none1() :: none()
  def t_none1(), do: nil

  @spec t_none2() :: no_return()
  def t_none2(), do: nil

  @spec t_module() :: module()
  def t_module(), do: nil

  @spec t_node() :: node()
  def t_node(), do: nil

  @spec t_complex_example1(integer(), %{key1: map()} | %{key2: integer()}) ::
          integer() | map()
  def t_complex_example1(_, _), do: nil
end
