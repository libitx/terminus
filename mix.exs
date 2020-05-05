defmodule Terminus.MixProject do
  use Mix.Project

  def project do
    [
      app: :terminus,
      version: "0.0.3",
      elixir: "~> 1.10",
      elixirc_paths: elixirc_paths(Mix.env),
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      name: "Terminus",
      description: "Crawl and subscribe to Bitcoin transaction events using Bitbus, Bitsocket and BitFS.",
      source_url: "https://github.com/libitx/terminus",
      docs: [
        main: "Terminus",
        groups_for_modules: [
          "Internals": [
            Terminus.HTTPStream,
            Terminus.HTTP.Client,
            Terminus.HTTP.Response
          ]
        ]
      ],
      package: [
        name: "terminus",
        files: ~w(lib .formatter.exs mix.exs README.md LICENSE.md),
        licenses: ["MIT"],
        links: %{
          "GitHub" => "https://github.com/libitx/terminus"
        }
      ]
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      applications: applications(Mix.env),
      extra_applications: [:logger]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:castore, "~> 0.1"},
      {:ex_doc, "~> 0.21", only: :dev, runtime: false},
      {:gen_stage, "~> 1.0"},
      {:jason, "~> 1.2"},
      {:mint, "~> 1.0"},
      {:plug_cowboy, "~> 2.1", only: :test},
      {:sse, "~> 0.4.0", only: :test}
    ]
  end

  defp applications(:test), do: applications(:default) ++ [:cowboy, :plug]
  defp applications(_),     do: []

  defp elixirc_paths(:test), do: elixirc_paths(:default) ++ ["test/support"]
  defp elixirc_paths(_), do: ["lib"]
end
