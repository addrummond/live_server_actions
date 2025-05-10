defmodule LiveServerActions.TestSupport.MyServact do
  @moduledoc false

  use LiveServerActions, d_ts_output_dir: fn root -> Path.join(root, "assets") end

  @server_action true
  def pub_no_typespec(_socket, _arg1, _arg2), do: "foo"

  @server_action true
  defp priv_no_typespec(_socket, _arg1, _arg2, _arg3), do: "foo"

  @server_action true
  @spec pub_with_typespec(Phoenix.LiveView.Socket.t(), %{
          fruit: String.t(),
          another_key: %{foo: integer(), bar: String.t()}
        }) ::
          %{error: String.t()}
          | %{quote: String.t(), author: String.t(), year: integer()}
  def pub_with_typespec(_socket, _arg1), do: "foo"

  @server_action true
  @spec priv_with_typespec(Phoenix.LiveView.Socket.t(), %{fruit: String.t()}) ::
          %{error: String.t()}
          | %{quote: String.t(), author: String.t(), year: integer()}
  defp priv_with_typespec(_socket, _arg1), do: "foo"

  @server_action true
  def _日本語識別子(_socket, _arg1), do: "foo"
end
