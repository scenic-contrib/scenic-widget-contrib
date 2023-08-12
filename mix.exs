defmodule ScenicWidgets.MixProject do
  use Mix.Project

  def project do
    [
      app: :scenic_widget_contrib,
      version: "0.1.0",
      elixir: "~> 1.12",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: []
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:scenic, "~> 0.11.0-beta.0"},
      # {:scenic, git: "https://github.com/JediLuke/scenic", branch: "no_text_wrap"},
      {:font_metrics, "~> 0.5"},
      {:ex_doc, "~> 0.25", only: :dev},
      {:earmark, "~> 1.4", only: :dev},
      {:stream_data, "~> 0.5", only: :test}
    ]
  end
end
