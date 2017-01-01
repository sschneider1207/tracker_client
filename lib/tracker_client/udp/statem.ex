defmodule TrackerClient.UDP.Statem do
  @moduledoc """
  State machine that follows the UDP torrent tracker protocol.

  Definition:
  http://www.bittorrent.org/beps/bep_0015.html
  """
  @behaviour :gen_statem
  @initial_conn_id 0x41727101980
  require Logger
  alias TrackerClient.AnnounceResponse
  alias AnnounceResponse.Peer

  defmodule Data do
    @moduledoc false

    defstruct [
      uri: nil,
      ipv4: nil,
      socket: nil,
      from: nil,
      request_num: 0,
      timer: nil,
      tx: nil,
      params: nil,
      conn_id: nil,
      mon: nil,
      parent: nil
    ]

    def new(opts) do
      struct(__MODULE__, opts)
    end
  end

  @doc """
  Starts a state machine with the given url and parent params.
  """
  @spec start_link(String.t, Keyword.t) :: :gen_statem.start_ret
  def start_link(url, parent) do
    :gen_statem.start_link(__MODULE__, [url, parent], [])
  end

  @doc """
  Initiate the announcement.
  """
  @spec start_link(:gen_statem.server_ref, Keyword.t) ::
    {:ok, AnnounceResponse.t} |
    {:error, :timeout | term}
  def announce(pid, params) do
    :gen_statem.call(pid, {:announce, params})
  end

  @doc false
  def init([url, parent]) do
    uri = URI.parse(url)
    with {:ok, ipv4} <- get_ipv4(uri),
         {:ok, socket} <- :gen_udp.open(0, [{:active, true}, :binary]),
         mon = Process.monitor(parent)
    do
      {:ok, :connection_request, Data.new(uri: uri, socket: socket, ipv4: ipv4, mon: mon, parent: parent)}
    else
      {:error, err} -> {:stop, err}
    end
  end

  defp get_ipv4(%URI{host: host}) do
    host
    |> String.to_char_list()
    |> :inet.getaddr(:inet)
  end

  @doc false
  def handle_event({:call, from}, {:announce, params}, :connection_request, data) do
    #Logger.debug("sending connection request")
    case connect_request(data.socket, data.ipv4, data.uri.port) do
      {:ok, tx} ->
        timer = start_retry_timer(0)
        {:next_state, :connection_response, %{data| tx: tx, timer: timer, from: from, params: params, request_num: 0}}
      {:error, err} ->
        {:stop_and_reply, err, [{:reply, data.from, {:error, err}}]}
    end
  end
  def handle_event(:info, {:udp, socket, ipv4, port, <<3 :: 32-big-integer, tx :: 32-big-integer, msg :: binary>>}, _state, %{socket: socket, ipv4: ipv4, uri: %{port: port}, tx: tx} = data) do
    {:stop_and_reply, :err, [{:reply, data.from, {:error, msg}}]}
  end
  def handle_event(:info, {:udp, socket, ipv4, port, response_packet}, :connection_response, %{socket: socket, ipv4: ipv4, uri: %{port: port}, tx: tx} = data) do
    <<
      0 :: 32-big-integer,
      ^tx :: 32-big-integer,
      conn_id :: 64-big-integer,
    >> = response_packet
    :timer.cancel(data.timer)
    #Logger.debug("received connection response", conn_id: conn_id)
    #Logger.debug("sending announce request", conn_id: conn_id)
    case announce_request(data.socket, data.ipv4, data.uri.port, conn_id, data.params) do
      {:ok, tx} ->
        timer = start_retry_timer(0)
        set_conn_expiration()
        {:next_state, :announce_response, %{data| tx: tx, timer: timer, conn_id: conn_id, request_num: 0}}
      {:error, err} ->
        {:stop_and_reply, err, [{:reply, data.from, {:error, err}}]}
    end
  end
  def handle_event(:info, {:udp, socket, ipv4, port, response_packet}, :announce_response, %{socket: socket, ipv4: ipv4, uri: %{port: port}, tx: tx} = data) do
    <<
      1 :: 32-big-integer,
      ^tx :: 32-big-integer,
      interval :: 32-big-integer,
      leechers :: 32-big-integer,
      seeders :: 32-big-integer,
      peers_bin :: binary
    >> = response_packet
    peers = Peer.parse_binary_peers(peers_bin)
    :timer.cancel(data.timer)
    #Logger.debug("received announce response", conn_id: data.conn_id)
    reply = AnnounceResponse.new(interval, leechers, seeders, peers)
    {:stop_and_reply, :normal, [{:reply, data.from, {:ok, reply}}]}
  end
  def handle_event(:info, :retry, state, %{request_num: 8} = data) do
    #Logger.debug("too many retires", state: state)
    {:stop_and_reply, :timeout, [{:reply, data.from, {:error, :timeout}}]}
  end
  def handle_event(:info, :retry, state, data) do#when state in ~w(connection_response, announce_response)a do
    request_num = data.request_num + 1
    #Logger.debug("retrying request", request_num: request_num, state: state)
    fun = case state do
      :connection_response -> fn -> connect_request(data.socket, data.ipv4, data.uri.port) end
      :announce_response -> fn -> announce_request(data.socket, data.ipv4, data.uri.port, data.conn_id, data.params) end
    end
    case fun.() do
      {:ok, tx} ->
        timer = start_retry_timer(request_num)
        {:keep_state, %{data| tx: tx, timer: timer, request_num: request_num}}
      {:error, err} ->
        {:stop_and_reply, err, [{:reply, data.from, {:error, err}}]}
    end
  end
  def handle_event(:info, :conn_expired, _state, data) do
    #Logger.debug("conn_id expired")
    :timer.cancel(data.timer)
    #Logger.debug("sending connection request")
    case connect_request(data.socket, data.ipv4, data.uri.port) do
      {:ok, tx} ->
        timer = start_retry_timer(0)
        {:next_state, :connection_response, %{data| tx: tx, timer: timer, request_num: 0, conn_id: nil}}
      {:error, err} ->
        {:stop_and_reply, err, [{:reply, data.from, {:error, err}}]}
    end
  end
  def handle_event(:info, {:DOWN, mon, :process, parent, reason}, _state, %{mon: mon, parent: parent}) do
    #Logger.debug("shutting down due to parent dying", reason: reason)
    {:stop, :normal}
  end
  def handle_event(_event, _msg, _state, _data) do
    :keep_state_and_data
  end

  @doc false
  def terminate(_reason, _state, data) do
    :gen_udp.close(data.socket)
    :ok
  end

  defp connect_request(socket, ipv4, port) do
    tx = gen_transaction_id()
    packet = <<
      @initial_conn_id :: 64-big-integer,
      0 :: 32-big-integer,
      tx :: 32-big-integer
    >>
    case :gen_udp.send(socket, ipv4, port, packet) do
      :ok -> {:ok, tx}
      err -> err
    end
  end

  defp announce_request(socket, ipv4, port, conn_id, params) do
    tx = gen_transaction_id()
    packet = <<
      conn_id :: 64-big-integer,
      1 :: 32-big-integer,
      tx :: 32-big-integer,
      params[:info_hash] :: 20-binary,
      params[:peer_id] :: 20-binary,
      params[:downloaded] :: 64-big-integer,
      params[:left] :: 64-big-integer,
      params[:uploaded] :: 64-big-integer,
      event(params[:event]) :: 32-big-integer,
      0 :: 32-big-integer,
      0 :: 32-big-integer,
      params[:numwant] || -1 :: 32-big-integer,
      params[:port] :: 16-big-integer
    >>
    case :gen_udp.send(socket, ipv4, port, packet) do
      :ok -> {:ok, tx}
      err -> err
    end
  end


  defp event(nil), do: 0
  defp event(:completed), do: 1
  defp event(:started), do: 2
  defp event(:stopped), do: 3

  defp gen_transaction_id do
    <<tx :: 32-big-integer>> = :crypto.strong_rand_bytes(4)
    tx
  end

  defp start_retry_timer(request_num) do
    time = round(15 * :math.pow(2, request_num) * 1_000)
    {:ok, timer} = :timer.send_after(time, :retry)
    timer
  end

  defp set_conn_expiration do
    Process.send_after(self(), :conn_expired, 2 * 60 * 1_000)
  end

  @doc false
  def callback_mode, do: :handle_event_function

  @doc false
  def code_change(_old_vsn, _old_state, _old_data, _extra), do: {:stop, :not_supported}
end
