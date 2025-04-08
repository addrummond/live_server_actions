defmodule LiveServerActions.MixProject do
  use Mix.Project

  def project do
    [
      app: :live_server_actions,
      version: "0.2.0",
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      description: """
      Call Elixir functions from React, with optional type safety.
      """,
      package: package()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger],
      mod: {LiveServerActions.Application, []}
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      # {:dep_from_hexpm, "~> 0.3.0"}
      # {:dep_from_git, git: "https://github.com/elixir-lang/my_dep.git", tag: "0.1.0"}
      {:phoenix_live_view, "~> 1.0"},
      {:ex_doc, ">= 0.0.0", only: :dev, runtime: false}
    ]
  end

  defp package do
    [
      # These are the default files included in the package
      files: ~w(
        lib .formatter.exs mix.exs README* LICENSE* changelog.md
        assets/live_server_actions.d.ts
        assets/serialize.js
        assets/live_server_actions.js
      ),
      licenses: ["MIT"],
      links: %{
        "GitHub" => "https://github.com/addrummond/live_server_actions",
        "Changelog" => "https://github.com/addrummond/live_server_actions/blob/main/changelog.md"
      }
    ]
  end
end
