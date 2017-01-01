defmodule TrackerClient.Mixfile do
  use Mix.Project

  def project do
    [app: :tracker_client,
     version: "0.1.0",
     build_path: "../../_build",
     config_path: "../../config/config.exs",
     deps_path: "../../deps",
     lockfile: "../../mix.lock",
     elixir: "~> 1.3",
     build_embedded: Mix.env == :prod,
     start_permanent: Mix.env == :prod,
     description: description,
     package: package,
     deps: deps]
  end

  def application do
    [applications: [:logger, :benx, :gen_stage],
     mod: {TrackerClient.Application, []}]
  end

  defp deps do
    [{:benx, "~> 0.1.2"},
    {:gen_stage, "~> 0.10.0"},
     {:ex_doc, "~> 0.14.5", only: :dev}]
  end

  defp description do
    """
    Make announcements to torrent trackers via HTTP or UDP.
    """
  end

  defp package do
    [name: :tracker_client,
     files: ["lib", "mix.exs", "README*", "LICENSE*"],
     maintainers: ["Sam Schneider"],
     licenses: ["MIT"],
     links: %{github: "https://github.com/sschneider1207/tracker_client"}]
  end
end
