defmodule Permit.Ash.MixProject do
  use Mix.Project

  def project do
    [
      app: :permit_ash,
      version: "0.1.0",
      elixir: "~> 1.18",
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
      {:ash, "~> 3.0"},
      {:permit, "~> 0.4.1"}
    ]
  end
end
