defmodule MonkeyXland.Screen do
  @moduledoc """
  The game's 320×200 screen drawn into a client's picture: shown 4:3, as large as fits,
  centred between black bars (`Cauldron2D.Fit.letterbox/3` with the frame `{320, 240}`).
  """

  alias Cauldron2D.{Fit, Render}
  alias FrenchCurve.Raster
  alias MonkeyXland.Picture

  @frame {320, 240}
  @black {0, 0, 0, 255}

  @doc "The shape the screen is shown at, for a scene's `:frame`."
  @spec frame() :: {pos_integer(), pos_integer()}
  def frame, do: @frame

  @doc """
  The screen in a `{width, height}` picture whose pixels are `aspect` times as tall as
  wide, with `menu` (a `MonkeyXland.Menu`, or `nil`) drawn over it.
  """
  @spec raster(
          Picture.t() | nil,
          {pos_integer(), pos_integer()},
          number(),
          MonkeyXland.Menu.t() | nil
        ) :: Raster.t()
  def raster(screen, size, aspect, menu \\ nil)

  def raster(nil, {width, height}, _aspect, _menu),
    do: Raster.from_rgba(width, height, :binary.copy(<<0, 0, 0, 255>>, width * height))

  def raster(screen, {width, height} = size, aspect, menu) do
    {x, y, fitted_width, fitted_height} = Fit.letterbox(size, aspect, @frame)
    picture = {320, 200, screen |> with_menu(menu) |> Picture.rgba()}
    placement = %{position: {x * 1.0, y * 1.0}, scale: {fitted_width / 320, fitted_height / 200}}
    Render.render({width, height}, [{:sprite, picture, placement}], background: @black)
  end

  defp with_menu(screen, nil), do: screen
  defp with_menu(screen, menu), do: Picture.overlay(screen, MonkeyXland.Menu.lines(menu))
end
