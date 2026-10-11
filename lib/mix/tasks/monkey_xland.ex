defmodule Mix.Tasks.MonkeyXland do
  @shortdoc "Play The Secret of Monkey Island from your own copy in this terminal"

  @moduledoc """
  Plays The Secret of Monkey Island in the terminal from the owner's Special Edition
  install.

      mix monkey_xland --game "path/to/The Secret of Monkey Island Special Edition"

  `--game` defaults to the `MONKEYXLAND_GAME` environment variable. The directory is the
  one holding `Monkey1.pak` and `audio/`. `--picture` (or `CAULDRON_PICTURE`) is how the picture
  reaches a terminal that keeps images, as `Cauldron2D.Drafter.Client.Picture` reads it:
  any of `native`, `native:N`, `size:WxH`, `png` and `swap`, comma separated, or
  `none`; default `native:2,swap`. `--mute` plays no sound
  (`CAULDRON_MUTE=1` too).
  """

  use Mix.Task
  alias Cauldron2D.Drafter.Client.Picture

  @switches [game: :string, name: :string, picture: :string, mute: :boolean]

  @impl Mix.Task
  def run(argv) do
    {opts, _rest} = OptionParser.parse!(argv, strict: @switches)
    Mix.Task.run("app.start")
    dir = Keyword.get(opts, :game) || System.get_env("MONKEYXLAND_GAME")

    case dir && MonkeyXland.Assets.load(dir) do
      {:ok, _assets} ->
        play(opts)

      {:error, {:not_installed, absent}} ->
        Mix.raise("#{dir} is not a Special Edition install: it has no #{Enum.join(absent, ", ")}")

      {:error, reason} ->
        Mix.raise("could not read the game in #{dir}: #{inspect(reason)}")

      nil ->
        Mix.raise("give the game's directory: mix monkey_xland --game path/to/game")
    end
  end

  defp play(opts) do
    Code.ensure_loaded!(Cauldron2D.Drafter.Surface)
    Drafter.Widget.Registry.register(Cauldron2D.Drafter.Surface)

    Drafter.run(Cauldron2D.Drafter.Client,
      refresh_rate: "30fps",
      pixel_mouse: true,
      props: %{
        game: MonkeyXland.Client,
        username: Keyword.get(opts, :name, "guybrush"),
        picture: picture(opts[:picture]),
        mute: opts[:mute]
      }
    )
  end

  defp picture(nil), do: nil

  defp picture(options) do
    case Picture.parse(options) do
      {:ok, options} -> options
      {:error, message} -> Mix.raise("--picture: " <> message)
    end
  end
end
