alias Experimental.DynamicSupervisor
defmodule TrackerClient.UDP.ConnectionSupervisor do
  use DynamicSupervisor

  def start_link do
    DynamicSupervisor.start_link(__MODULE__, [], [name: __MODULE__])
  end

  @doc false
  def init([]) do
    children = [
      worker(TrackerClient.UDP.Statem, [], restart: :temporary)
    ]

    {:ok, children, strategy: :one_for_one}
  end

  def start_child(url) do
    DynamicSupervisor.start_child(__MODULE__, [url, self()])
  end
end
