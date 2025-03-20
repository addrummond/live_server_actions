defmodule CounterWeb.CounterLive do
  use Phoenix.LiveView
  use LiveServerActions

  alias LiveServerActions.Components

  def mount(_params, _session, socket) do
    {:ok, assign(socket, count: 0)}
  end

  def render(assigns) do
    ~H"""
    <Components.react_component id="my-counter" component="Counter" />
    """
  end

  @server_action true
  @spec update_count(Phoenix.LiveView.Socket.t(), integer()) :: %{new_count: integer()}
  defp update_count(_socket, inc) do
    %{new_count: :ets.update_counter(:counter, :counter, inc)}
  end
end
