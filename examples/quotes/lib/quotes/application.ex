defmodule Quotes.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      QuotesWeb.Telemetry,
      {DNSCluster, query: Application.get_env(:quotes, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: Quotes.PubSub},
      # Start the Finch HTTP client for sending emails
      {Finch, name: Quotes.Finch},
      # Start a worker by calling: Quotes.Worker.start_link(arg)
      # {Quotes.Worker, arg},
      # Start to serve requests, typically the last entry
      QuotesWeb.Endpoint
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Quotes.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    QuotesWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
