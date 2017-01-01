defmodule TrackerClient.AnnounceResponse.Peer do
  @moduledoc false

  @opaque t :: %__MODULE__{}

  defstruct [
    peer_id: nil,
    ip: nil,
    port: 0
  ]

  def new(ip, port, peer_id \\ nil) do
    struct(__MODULE__, peer_id: peer_id, ip: ip, port: port)
  end

  def parse_binary_peers(peers) when is_binary(peers) do
    do_parse_binary_peers(peers)
  end

  defp do_parse_binary_peers(peers, acc \\ [])
  defp do_parse_binary_peers(<<>>, acc), do: acc
  defp do_parse_binary_peers(<<
    ip1 :: 8-big-integer,
    ip2 :: 8-big-integer,
    ip3 :: 8-big-integer,
    ip4 :: 8-big-integer,
    port :: 16-big-integer,
    rest :: binary>>, acc)
  do
    do_parse_binary_peers(rest, [new({ip1, ip2, ip3, ip4}, port)|acc])
  end
end
