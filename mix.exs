defmodule Terminus.MixProject do
  use Mix.Project

  def project do
    [
      app: :terminus,
      version: "0.1.0",
      elixir: "~> 1.10",
      start_permanent: Mix.env() == :prod,
      deps: deps()
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
      {:castore, "~> 0.1"},
      {:ex_doc, "~> 0.21", only: :dev, runtime: false},
      {:gen_stage, "~> 1.0"},
      {:jason, "~> 1.2"},
      {:mint, "~> 1.0"}
    ]
  end
end
