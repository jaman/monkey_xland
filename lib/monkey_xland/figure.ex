defmodule MonkeyXland.Figure do
  @moduledoc """
  An actor as drawn: the picture of each limb, where it goes in the room, and the
  rectangle they cover together.

  Limbs are placed one after another: each picture sits at its own offset from the
  actor's feet plus the moves of the limbs before it. Facing west, a costume that allows
  it is drawn mirrored about the actor's x. An actor scaled below 255 has its pictures
  and offsets shrunk in proportion. Costume colours go through the costume's palette,
  then through the actor's own (`actor_ops palette`).
  """

  alias MonkeyXland.{Actor, Assets}
  alias MonkeyXland.Scumm.{Costume, Image}
  alias MonkeyXland.Scumm.Costume.Frame

  @type piece :: %{limb: 0..15, image: Image.t(), x: integer(), y: integer()}

  @doc "The pieces actor `actor` is drawn with, in drawing order, in room pixels."
  @spec pieces(Actor.t()) :: [piece()]
  def pieces(%Actor{costume: 0}), do: []

  def pieces(%Actor{} = actor) do
    case Assets.costume(actor.costume) do
      nil -> []
      costume -> place(actor, costume)
    end
  end

  @doc "The room rectangle `{left, top, right, bottom}` an actor covers, or `nil` when it shows nothing."
  @spec bounds(Actor.t()) :: {integer(), integer(), integer(), integer()} | nil
  def bounds(actor) do
    case pieces(actor) do
      [] -> nil
      pieces -> Enum.reduce(pieces, nil, &grow/2)
    end
  end

  defp grow(%{x: x, y: y, image: %Image{width: width, height: height}}, nil),
    do: {x, y, x + width, y + height}

  defp grow(
         %{x: x, y: y, image: %Image{width: width, height: height}},
         {left, top, right, bottom}
       ),
       do: {min(left, x), min(top, y), max(right, x + width), max(bottom, y + height)}

  defp place(actor, costume) do
    costume = %{costume | palette: own_palette(costume.palette, actor.palette)}
    mirror = costume.mirror? and Actor.direction(actor.facing) == 0
    view = %{actor: actor, costume: costume, mirror: mirror, base_y: actor.y - actor.elevation}

    actor
    |> Actor.showing(costume)
    |> Enum.reduce({[], 0, 0}, fn {limb, number}, placed ->
      costume |> frame(limb, number) |> piece(limb, placed, view)
    end)
    |> elem(0)
    |> Enum.reverse()
  end

  defp piece(nil, _limb, placed, _view), do: placed

  defp piece(%Frame{} = frame, limb, {pieces, move_x, move_y}, view) do
    %{actor: actor, costume: costume, mirror: mirror, base_y: base_y} = view
    {scale_x, scale_y} = actor.scale
    offset_x = scaled(move_x + frame.rel_x, scale_x)
    offset_y = scaled(move_y + frame.rel_y, scale_y)
    image = costume |> Costume.to_image(frame, mirror) |> shrink(scale_x, scale_y)
    x = if mirror, do: actor.x - offset_x - image.width, else: actor.x + offset_x
    piece = %{limb: limb, image: image, x: x, y: base_y + offset_y}
    {[piece | pieces], move_x + frame.move_x, move_y - frame.move_y}
  end

  defp frame(%Costume{limbs: limbs}, limb, number) do
    limbs |> Enum.at(limb, []) |> Enum.at(number)
  end

  defp scaled(value, 255), do: value
  defp scaled(value, scale), do: div(value * scale, 255)

  defp own_palette(costume_palette, overrides) do
    costume_palette
    |> Enum.with_index()
    |> Enum.map(fn {color, index} -> overrides |> Map.get(index, 0xFF) |> chosen(color) end)
  end

  defp chosen(0xFF, color), do: color
  defp chosen(override, _color), do: override

  defp shrink(image, 255, 255), do: image

  defp shrink(%Image{width: width, height: height} = image, scale_x, scale_y) do
    new_width = max(div(width * scale_x, 255), 1)
    new_height = max(div(height * scale_y, 255), 1)
    columns = for x <- 0..(new_width - 1), do: min(div(x * 255, scale_x), width - 1)
    rows = for y <- 0..(new_height - 1), do: min(div(y * 255, scale_y), height - 1)

    %Image{
      width: new_width,
      height: new_height,
      pixels: resample(image.pixels, width, rows, columns),
      mask: resample(image.mask, width, rows, columns)
    }
  end

  defp resample(nil, _width, _rows, _columns), do: nil

  defp resample(bytes, width, rows, columns) do
    for row <- rows,
        line = binary_part(bytes, row * width, width),
        column <- columns,
        into: <<>>,
        do: <<:binary.at(line, column)>>
  end
end
