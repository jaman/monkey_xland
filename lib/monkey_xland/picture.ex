defmodule MonkeyXland.Picture do
  @moduledoc """
  The 320×200 screen of a world as palette indices, and its palette.

  Drawn in order: the room under the camera in the room's rows of the screen; its
  objects, last in the room's list first, each in the picture of its state; boxes
  scripts drew; the actors in the room, those nearer the top of the screen first, each
  hidden where the z-plane of its box (or the one `actor_ops` forced) covers it — a plane
  being the room's and any shown object's; the text on screen; the verbs, lit under the
  pointer and dimmed when dimmed; and the cursor. While a script has the screen shaking
  the whole picture is shown shifted up by the shake's pixels (`MonkeyXland.Shake`), black
  below.

      %{pixels: pixels, palette: palette} = MonkeyXland.Picture.draw(world)
  """

  import Bitwise

  alias MonkeyXland.{Actor, Assets, Boxes, Camera, Figure, Message, Objects, Shake, Verbs, World}
  alias MonkeyXland.Scumm.{Charset, Image, ZPlane}

  @width 320
  @height 200
  @never_clip 20

  @type t :: %{pixels: binary(), palette: binary()}

  @doc "The screen of `world`."
  @spec draw(World.t()) :: t()
  def draw(%World{} = world) do
    rows = List.duplicate(:binary.copy(<<0>>, @width), @height) |> List.to_tuple()

    rows
    |> room(world)
    |> draw_boxes(world)
    |> actors(world)
    |> text(world)
    |> verbs(world)
    |> cursor(world)
    |> shaken(world)
    |> then(&%{pixels: IO.iodata_to_binary(&1), palette: palette(world)})
  end

  @doc """
  A screen with a menu drawn over it: a dark panel with `title` and the lines below it,
  the chosen line (marked `true`) highlighted, in the game's font 2.
  """
  @spec overlay(t(), {String.t(), [{String.t(), boolean()}]}) :: t()
  def overlay(%{pixels: pixels} = screen, {title, lines}) do
    charset = Assets.charset(2)
    rows = for <<row::binary-size(@width) <- pixels>>, do: row
    rows = List.to_tuple(rows)
    height = (length(lines) + 2) * charset.height + 8
    top = div(@height - height, 2)
    panel = :binary.copy(<<0>>, 280)
    rows = Enum.reduce(top..(top + height)//1, rows, &put_segment(&2, &1, 20, panel, nil))
    world = %World{objects: %{}, charset: 2}

    texts = [
      {title, 14} | Enum.map(lines, fn {text, chosen} -> {text, if(chosen, do: 15, else: 7)} end)
    ]

    rows =
      texts
      |> Enum.with_index()
      |> Enum.reduce(rows, fn {{text, color}, index}, acc ->
        y = top + 4 + index * charset.height + if(index > 0, do: charset.height, else: 0)
        draw_line(acc, world, charset, {30, y, [{text, color}]}, 0)
      end)

    %{screen | pixels: rows |> Tuple.to_list() |> IO.iodata_to_binary()}
  end

  @doc "A screen as RGB bytes, three per pixel."
  @spec rgb(t()) :: binary()
  def rgb(%{pixels: pixels, palette: palette}) do
    colors = for <<rgb::binary-3 <- palette>>, do: rgb
    lookup = List.to_tuple(colors ++ List.duplicate(<<0, 0, 0>>, 256 - length(colors)))
    for <<index <- pixels>>, into: <<>>, do: elem(lookup, index)
  end

  @doc "A screen as RGBA bytes, four per pixel, every pixel opaque."
  @spec rgba(t()) :: binary()
  def rgba(%{pixels: pixels, palette: palette}) do
    colors = for <<rgb::binary-3 <- palette>>, do: rgb <> <<255>>
    lookup = List.to_tuple(colors ++ List.duplicate(<<0, 0, 0, 255>>, 256 - length(colors)))
    for <<index <- pixels>>, into: <<>>, do: elem(lookup, index)
  end

  defp palette(%World{palette: <<>>}), do: :binary.copy(<<0>>, 768)
  defp palette(%World{palette: palette}), do: palette

  defp shaken(rows, world), do: shift_up(Tuple.to_list(rows), Shake.offset(world))

  defp shift_up(rows, 0), do: rows

  defp shift_up(rows, offset),
    do: Enum.drop(rows, offset) ++ List.duplicate(:binary.copy(<<0>>, @width), offset)

  defp room(rows, %World{room_data: nil}), do: rows
  defp room(rows, %World{lights: lights}) when (lights &&& 2) == 0, do: rows

  defp room(rows, %World{room_data: data} = world) do
    left = Camera.left(world)
    view = min(world.screen.height, data.background.height)
    width = min(@width, data.background.width)

    rows =
      Enum.reduce(0..(view - 1)//1, rows, fn y, acc ->
        line = binary_part(data.background.pixels, y * data.background.width + left, width)
        put_segment(acc, world.screen.top + y, 0, line, nil)
      end)

    objects(rows, world, left)
  end

  defp objects(rows, world, left) do
    world
    |> shown_objects()
    |> Enum.reverse()
    |> Enum.reduce(rows, fn {_object, %{image: image}, {x, y}}, acc ->
      blit(acc, image, x - left, y + world.screen.top, fn _x, _y -> true end)
    end)
  end

  defp shown_objects(world) do
    for object <- world.room_objects,
        state = World.object(world, object.number).state,
        state > 0,
        object.image != nil,
        picture = Enum.at(object.image.states, state - 1),
        picture != nil,
        Objects.parents_shown?(world, object) do
      {object, picture, picture_position(world, object)}
    end
  end

  defp picture_position(world, object) do
    case Map.get(world.positions, object.number) do
      nil -> {object.image.x, object.image.y}
      position -> position
    end
  end

  defp draw_boxes(rows, world) do
    Enum.reduce(world.boxes.drawn, rows, fn {x1, y1, x2, y2, color}, acc ->
      line = :binary.copy(<<color>>, max(x2 - x1 + 1, 0))
      Enum.reduce(max(y1, 0)..min(y2, @height - 1)//1, acc, &put_segment(&2, &1, x1, line, nil))
    end)
  end

  defp actors(rows, %World{room_data: nil}), do: rows

  defp actors(rows, world) do
    left = Camera.left(world)
    planes = planes(world)

    world
    |> World.actors_in_room()
    |> Enum.filter(& &1.visible)
    |> Enum.sort_by(&{&1.y, &1.number})
    |> Enum.reduce(rows, fn actor, acc -> draw_actor(acc, world, actor, left, planes) end)
  end

  defp draw_actor(rows, world, actor, left, planes) do
    plane = plane_for(world, actor)
    hidden = fn x, y -> masked?(planes, plane, x, y) end

    actor
    |> Figure.pieces()
    |> Enum.reduce(rows, fn %{image: image, x: x, y: y}, acc ->
      blit(acc, image, x - left, y + world.screen.top, fn sx, sy ->
        not hidden.(sx + left, sy - world.screen.top)
      end)
    end)
  end

  defp plane_for(world, %Actor{number: number, z_clip: :auto, box: box}) do
    if Objects.class?(world, number, @never_clip), do: 0, else: box_mask(world, box)
  end

  defp plane_for(_world, %Actor{z_clip: plane}), do: plane

  defp box_mask(world, box) do
    case Map.get(Boxes.all(world), box) do
      nil -> 0
      found -> found.mask
    end
  end

  defp planes(world) do
    room_planes =
      world.room_data.z_planes
      |> Enum.with_index(1)
      |> Enum.map(fn {plane, n} -> {n, plane, {0, 0}} end)

    object_planes =
      for {_object, picture, {x, y}} <- shown_objects(world),
          {plane, n} <- Enum.with_index(picture.z_planes, 1),
          do: {n, plane, {x, y}}

    Enum.group_by(room_planes ++ object_planes, &elem(&1, 0), fn {_n, plane, origin} ->
      {plane, origin}
    end)
  end

  defp masked?(_planes, 0, _x, _y), do: false

  defp masked?(planes, plane, x, y) do
    planes
    |> Map.get(plane, [])
    |> Enum.any?(fn {%ZPlane{width: width, height: height} = z, {ox, oy}} ->
      px = x - ox
      py = y - oy
      px >= 0 and py >= 0 and px < width and py < height and ZPlane.set?(z, {px, py})
    end)
  end

  defp text(rows, world) do
    rows
    |> message(world)
    |> saved_texts(world)
  end

  defp message(rows, %World{message: nil}), do: rows

  defp message(rows, %World{message: %Message{} = message} = world) do
    charset = Assets.charset(message.settings.charset)
    top = if message.actor != 0xFF or message.settings.overhead, do: world.screen.top, else: 0

    message
    |> Message.lines(charset)
    |> Enum.reduce(rows, &draw_line(&2, world, charset, &1, top))
  end

  defp saved_texts(rows, world) do
    Enum.reduce(world.saved_text, rows, fn {_key, %{settings: settings, pages: pages}}, acc ->
      charset = Assets.charset(settings.charset)

      message = %Message{
        actor: 0xFF,
        pages: pages,
        settings: settings,
        position: {settings.x, settings.y},
        shown: Enum.at(pages, 0, [])
      }

      message |> Message.lines(charset) |> Enum.reduce(acc, &draw_line(&2, world, charset, &1, 0))
    end)
  end

  defp draw_line(rows, _world, nil, _line, _top), do: rows

  defp draw_line(rows, world, %Charset{} = charset, {x, y, runs}, top) do
    {rows, _x} =
      Enum.reduce(runs, {rows, x}, fn {text, color}, {acc, pen} ->
        for <<code <- text>>, reduce: {acc, pen} do
          {inner, at} ->
            draw_glyph(inner, world, charset, Map.get(charset.glyphs, code), color, at, y + top)
        end
      end)

    rows
  end

  defp draw_glyph(rows, _world, _charset, nil, _color, x, _y), do: {rows, x}

  defp draw_glyph(rows, world, charset, glyph, color, x, y) do
    colors = Map.get(world.charset_colors, world.charset, nil)

    lookup = fn
      1 -> color
      value -> font_color(colors, charset, value)
    end

    pixels =
      for <<value <- glyph.pixels>>,
        into: <<>>,
        do: <<if(value == 0, do: 0, else: lookup.(value))>>

    mask = for <<value <- glyph.pixels>>, into: <<>>, do: <<min(value, 1)>>
    image = %Image{width: glyph.width, height: glyph.height, pixels: pixels, mask: mask}

    {blit(rows, image, x + glyph.x, y + glyph.y, fn _x, _y -> true end),
     x + glyph.width + glyph.x}
  end

  defp font_color(nil, charset, value), do: Enum.at(charset.colors, value - 1, value)

  defp font_color(colors, charset, value),
    do: Enum.at(colors, value, font_color(nil, charset, value))

  defp verbs(rows, world) do
    hovered = Verbs.at(world, world.mouse)

    world.verbs
    |> Map.values()
    |> Enum.filter(&(&1.mode != 0 and &1.save_id == 0 and is_binary(&1.name)))
    |> Enum.sort_by(& &1.id)
    |> Enum.reduce(rows, fn verb, acc ->
      charset = Assets.charset(verb.charset)
      {left, top, _right, _bottom} = Verbs.rect(verb)

      draw_line(
        acc,
        %{world | charset: verb.charset},
        charset,
        {left, top, [{verb.name, verb_color(verb, hovered)}]},
        0
      )
    end)
  end

  defp verb_color(%{mode: 2, dim_color: color}, _hovered), do: color
  defp verb_color(%{id: id, hi_color: color}, %{id: id}) when color != 0, do: color
  defp verb_color(%{color: color}, _hovered), do: color

  defp cursor(rows, %World{cursor: %{state: state}}) when state <= 0, do: rows

  defp cursor(rows, %World{mouse: {x, y}}) do
    arms = for offset <- [-6, -5, -4, -3, 3, 4, 5, 6], do: offset
    points = for(dx <- arms, do: {x + dx, y}) ++ for(dy <- arms, do: {x, y + dy})
    Enum.reduce(points, rows, fn {px, py}, acc -> put_segment(acc, py, px, <<15>>, nil) end)
  end

  defp blit(
         rows,
         %Image{width: width, height: height, pixels: pixels, mask: mask},
         x,
         y,
         visible?
       ) do
    Enum.reduce(0..(height - 1)//1, rows, fn row, acc ->
      line = binary_part(pixels, row * width, width)
      line_mask = if mask, do: binary_part(mask, row * width, width), else: nil

      put_segment(acc, y + row, x, line, line_mask, fn column ->
        visible?.(x + column, y + row)
      end)
    end)
  end

  defp put_segment(rows, y, x, line, mask, visible? \\ fn _column -> true end)

  defp put_segment(rows, y, _x, _line, _mask, _visible?) when y < 0 or y >= @height, do: rows

  defp put_segment(rows, y, x, line, mask, visible?) do
    first = max(0, -x)
    last = min(byte_size(line), @width - x)

    if last <= first do
      rows
    else
      row = elem(rows, y)
      start = x + first
      old = binary_part(row, start, last - first)

      new =
        merge(
          old,
          binary_part(line, first, last - first),
          mask && binary_part(mask, first, last - first),
          first,
          visible?
        )

      put_elem(
        rows,
        y,
        binary_part(row, 0, start) <>
          new <> binary_part(row, start + (last - first), @width - start - (last - first))
      )
    end
  end

  defp merge(_old, new, nil, _first, _visible?), do: new

  defp merge(old, new, mask, first, visible?) do
    for {{o, n, m}, column} <-
          Enum.with_index(
            Enum.zip([
              :binary.bin_to_list(old),
              :binary.bin_to_list(new),
              :binary.bin_to_list(mask)
            ]),
            first
          ),
        into: <<>>,
        do: <<if((m &&& 1) == 1 and visible?.(column), do: n, else: o)>>
  end
end
