defmodule LiveServerActions.Components do
  @moduledoc """
  This module provides a helper function to render a React component in a
  Phoenix LiveView.
  """

  use Phoenix.Component

  attr(:component, :string, required: true)
  attr(:id, :string, required: true)
  attr(:props, :map, required: false)

  @doc """
  Renders a React component in a Phoenix LiveView. The `props` attr must be a
  suitable argument to `JSON.encode!/1`.
  """
  def react_component(assigns) do
    ~H"""
    <div
      id={@id}
      phx-update="ignore"
      phx-hook="ServerAction"
      data-react-component-name={@component}
      data-react-component-props={JSON.encode!(assigns[:props] || %{})}
    >
      <% # The react root %>
      <div></div>
    </div>
    """
  end
end
