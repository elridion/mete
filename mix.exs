defmodule Mete.MixProject do
  use Mix.Project

  @version "2.1.0"

  def project do
    [
      app: :mete,
      version: @version,
      elixir: "~> 1.9",
      start_permanent: Mix.env() == :prod,
      description: description(),
      package: package(),
      deps: deps(),
      docs: docs(),
      dialyzer: [plt_add_apps: [:mix]]
      # elixirc_paths: elixirc_paths(Mix.env())
    ]
  end

  # def elixirc_paths(_), do: ["lib"]

  def application do
    [
      mod: {Mete.Application, []},
      extra_applications: [:logger, :inets, :runtime_tools]
    ]
  end

  defp deps do
    [
      {:hackney, "~> 1.18", optional: true},
      {:ex_doc, "~> 0.20", only: :dev},
      {:credo, "~> 1.2", only: :dev}
    ]
  end

  defp description do
    "Basic measuring tool and telemetry writer using InfluxDB."
  end

  defp docs do
    [
      main: "Mete",
      canonical: "http://hexdocs.pm/mete",
      source_url: "https://github.com/elridion/mete"
    ]
  end

  defp package() do
    [
      maintainers: ["Hans Bernhard Gödeke"],
      files: ~w(lib .formatter.exs mix.exs README* LICENSE),
      licenses: ["GPL-3.0-only"],
      links: %{
        "GitHub" => "https://github.com/elridion/mete"
      }
    ]
  end
end
