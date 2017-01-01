alias TrackerClient.UDP.Statem

tracker = "udp://tracker.coppersurfer.tk:6969"
{:ok, pid} = Statem.start_link(tracker)
Statem.announce(pid, [])
