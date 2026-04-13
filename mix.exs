defmodule PhoenixSyncFix.MixProject do
  use Mix.Project

  def project do
    [
      app: :phoenix_sync_fix,
      version: "0.1.0",
      elixir: "~> 1.20-rc",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      description: "Phoenix.Sync fork for debugging mix igniter.install",
      package: [
        licenses: ["Apache-2.0"],
        links: %{
          "GitHub" => "https://github.com/spapiernik/phoenix_sync_fix",
          "Phoenix.Sync original" => "https://hex.pm/packages/phoenix_sync"
        },
        source_url: "https://github.com/spapiernik/phoenix_sync_fix"
      ]
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:ex_doc, ">= 0.0.0", only: :dev, runtime: false},
      {:igniter, "~> 0.6", optional: true}
      # {:dep_from_hexpm, "~> 0.3.0"},
      # {:dep_from_git, git: "https://github.com/elixir-lang/my_dep.git", tag: "0.1.0"}
    ]
  end
end
