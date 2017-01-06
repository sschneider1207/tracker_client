defmodule TrackerClient.Announcement do
  @moduledoc false

  @opaque t :: %__MODULE__{}

  defstruct [
    interval: nil,
    leechers: 0,
    seeders: 0,
    peers: [],
    trackerid: nil
  ]

  def new(interval, leechers, seeders, peers, trackerid \\ nil) do
    struct(__MODULE__, interval: interval, leechers: leechers, seeders: seeders, peers: peers, trackerid: trackerid)
  end
end
