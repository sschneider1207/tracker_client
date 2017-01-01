defmodule TrackerClient.UDP do
  @moduledoc """
  Make announcements to trackers implementing the UDP tracking protocol.
  """
  @behaviour TrackerClient
  alias TrackerClient.UDP.{Statem, ConnectionSupervisor}

  def announce(url, params) do
    with {:ok, pid} <- ConnectionSupervisor.start_child(url),
         {:ok, response} <- Statem.announce(pid, params)
    do
      {:ok, response}
    else
      {:error, :timeout} ->
        {:error, "timeout"}
      _ ->
        {:error, "udp error"}
    end
  end
end
