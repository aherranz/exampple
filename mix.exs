defmodule Exampple.MixProject do
  use Mix.Project

  def project do
    [
      app: :exampple,
      version: "0.7.1",
      description: "eXaMPPle is a XMPP Component Framework",
      elixir: "~> 1.9",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      consolidate_protocols: Mix.env() != :test,
      dialyzer: [plt_add_apps: [:mix]],
      deps: deps(),
      aliases: aliases(),
      package: package(),
      docs: docs(),
      test_coverage: [tool: ExCoveralls],
      preferred_cli_env: [
        coveralls: :test,
        "coveralls.detail": :test,
        "coveralls.json": :test,
        "coveralls.html": :test,
        "coveralls.post": :test,
        "coveralls.travis": :test,
        "travis-ci": :test,
        inch: :docs
      ]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger, :crypto, :ssl],
      mod: {Exampple.Application, []}
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:gen_state_machine, "~> 2.1"},
      {:saxy, "~> 1.2"},
      {:telemetry, "~> 0.4"},
      {:telemetry_poller, "~> 0.4"},
      {:telemetry_metrics, "~> 0.4"},
      {:uuid, "~> 1.1"},
      {:ex_doc, ">= 0.0.0", optional: true, only: :dev},
      {:inch_ex, ">= 0.0.0", optional: true, only: :docs},
      {:dialyxir, "~> 1.0", optional: true, only: :dev, runtime: false},
      {:excoveralls, "~> 0.13", optional: true, only: :test}
    ]
  end

  defp aliases do
    [
      "travis-ci": [
        "local.hex --force",
        "local.rebar --force",
        "deps.get",
        "coveralls.travis"
      ]
    ]
  end

  defp package do
    [
      files: ["config", "lib", "mix.exs", "mix.lock", "README*", "COPYING*"],
      maintainers: ["Manuel Rubio"],
      licenses: ["LGPL 2.1"],
      links: %{"GitHub" => "https://github.com/altenwald/exampple"}
    ]
  end

  defp docs do
    [
      main: "readme",
      extras: ["README.md"]
    ]
  end
end
