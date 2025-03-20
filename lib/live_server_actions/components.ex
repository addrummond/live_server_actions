defmodule LiveServerActions.Components do
  use Phoenix.Component

  attr(:component, :string, required: true)
  attr(:id, :string, required: true)
  attr(:props, :map, required: false)

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
