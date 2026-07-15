defmodule ReqManagedAgentsHost.MixProject do
  use Mix.Project

  @version "0.1.0"
  @source_url "https://github.com/cash-mckeeman/req_managed_agents_host"

  def project do
    [
      app: :req_managed_agents_host,
      version: @version,
      elixir: "~> 1.16",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      description:
        "Durable single-node session host for req_managed_agents: crash-survivable, " <>
          "idle-detachable hosted sessions keyed by an external id.",
      package: package(),
      name: "req_managed_agents_host",
      source_url: @source_url,
      docs: docs()
    ]
  end

  def application do
    [mod: {ReqManagedAgents.Host.Application, []}, extra_applications: [:logger]]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      {:req_managed_agents, "~> 0.9"},
      {:jason, "~> 1.4"},
      {:mox, "~> 1.1", only: :test},
      {:ex_doc, "~> 0.34", only: :dev, runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false}
    ]
  end

  defp package do
    [
      licenses: ["Apache-2.0"],
      links: %{"GitHub" => @source_url}
    ]
  end

  defp docs do
    [main: "readme", extras: ["README.md"], source_ref: "v#{@version}"]
  end
end
