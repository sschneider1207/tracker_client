defmodule TrackerClient.Application do
  @moduledoc false
  use Application

  def start(_type, _args) do
    import Supervisor.Spec, warn: false

    children = [
      supervisor(TrackerClient.UDP.ConnectionSupervisor, []),
    ]

    opts = [strategy: :one_for_one, name: TrackerClient.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
