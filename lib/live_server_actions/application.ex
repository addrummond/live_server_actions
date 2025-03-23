defmodule LiveServerActions.Application do
  @moduledoc false

  @behaviour Application
  @behaviour Supervisor

  def start(_type, args) do
    :ets.new(:live_server_actions_type_spec_lookup, [
      :public,
      :set,
      :named_table,
      {:read_concurrency, true}
    ])

    Supervisor.start_link(__MODULE__, args, strategy: :one_for_one)
  end

  def stop(_state) do
    :ok
  end

  def init(_args) do
    Supervisor.init([], strategy: :one_for_one)
  end
end
