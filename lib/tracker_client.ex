defmodule TrackerClient do
  @moduledoc """
  Callback for sending announcements to different types of tracker implementations.
  """
  alias TrackerClient.AnnounceResponse

  @doc """
  Make an announcement to the given tracker.
  """
  @callback announce(url :: String.t, params :: Keyword.t) ::
    {:ok, AnnounceResponse.t} |
    {:error, String.t}
end
