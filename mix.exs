defmodule MonkeyXland.MixProject do
  use Mix.Project

  @version "0.1.0"
  @source_url "https://github.com/jaman/monkey_xland"

  def project do
    [
      app: :monkey_xland,
      version: @version,
      elixir: "~> 1.18",
      elixirc_options: [warnings_as_errors: true],
      start_permanent: Mix.env() == :prod,
      description: "The Secret of Monkey Island, played from the owner's own copy, on Cauldron.",
      source_url: @source_url,
      package: package(),
      docs: docs(),
      deps: deps()
    ]
  end

  def application do
    [extra_applications: [:logger]]
  end

  defp package do
    [
      licenses: ["GPL-2.0-or-later"],
      links: %{"GitHub" => @source_url},
      files: ~w(lib mix.exs .formatter.exs README.md CHANGELOG.md LICENSE)
    ]
  end

  defp docs do
    [
      main: "readme",
      source_ref: "v" <> @version,
      source_url: @source_url,
      extras: ["README.md", "CHANGELOG.md"]
    ]
  end

  defp deps do
    [
      family(:grog_vm, "~> 0.1.0", "../grog_vm", []),
      family(:cauldron_2d, "~> 0.2.2", "../cauldron/cauldron_2d", []),
      family(:cauldron_2d_drafter, "~> 0.2.2", "../cauldron/cauldron_2d_drafter", []),
      family(:linocut, "~> 0.2.2", "../cauldron/linocut", override: true),
      family(:drafter, "~> 0.5.0", "../drafter", override: true),
      family(:french_curve, "~> 0.2.0", "../french_curve", override: true),
      family(:tuning_fork, "~> 0.1.12", "../tuning_fork/tuning_fork", override: true),
      family(:tuning_fork_speaker, "~> 0.1.12", "../tuning_fork/tuning_fork_speaker", []),
      family(:tuning_fork_mt32, "~> 0.1.12", "../tuning_fork/tuning_fork_mt32", []),
      family(:tuning_fork_wma, "~> 0.1.12", "../tuning_fork/tuning_fork_wma", []),
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:ex_doc, "~> 0.34", only: :dev, runtime: false}
    ]
  end

  defp family(app, requirement, path, opts) do
    if System.get_env("PLUMB_HEX") == nil and File.dir?(path),
      do: {app, [path: path] ++ opts},
      else: {app, requirement, Keyword.delete(opts, :override)}
  end
end
