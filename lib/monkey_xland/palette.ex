defmodule MonkeyXland.Palette do
  @moduledoc """
  The colours on screen: the room's palette as scripts change it, its brightness, and the
  ranges that cycle.

  `base_palette` is the room's own palette (with colours scripts set), from which
  brightness changes are worked out; `palette` is what is shown.
  """

  import Bitwise

  alias MonkeyXland.Scumm.Room.Cycle
  alias MonkeyXland.World

  @doc "The palette and cycles of the room just entered."
  @spec enter_room(World.t()) :: World.t()
  def enter_room(%World{room_data: room} = world) do
    cycles = Enum.map(room.cycles, &%{cycle: &1, counter: 0})
    %{world | palette: room.palette, base_palette: room.palette, cycles: cycles}
  end

  @doc "Sets colour `index` to `{r, g, b}` in both palettes."
  @spec set_color(World.t(), integer(), integer(), integer(), integer()) :: World.t()
  def set_color(world, index, red, green, blue) when index in 0..255 do
    rgb = <<clamp(red), clamp(green), clamp(blue)>>

    %{
      world
      | palette: put_rgb(world.palette, index, rgb),
        base_palette: put_rgb(world.base_palette, index, rgb)
    }
  end

  def set_color(world, _index, _red, _green, _blue), do: world

  @doc "Colours `first..last` at `red`, `green`, `blue` parts in 255 of the room's own."
  @spec intensity(World.t(), integer(), integer(), integer(), integer(), integer()) :: World.t()
  def intensity(%World{base_palette: base} = world, red, green, blue, first, last) do
    range = max(first, 0)..min(last, 255)//1

    palette =
      Enum.reduce(range, world.palette, fn index, palette ->
        <<r, g, b>> = binary_part(base, index * 3, 3)
        put_rgb(palette, index, <<scaled(r, red), scaled(g, green), scaled(b, blue)>>)
      end)

    %{world | palette: palette}
  end

  @doc "Advances every cycle by `jiffies`, rotating the ranges whose time has come."
  @spec cycle(World.t(), non_neg_integer()) :: World.t()
  def cycle(%World{cycles: cycles} = world, jiffies) do
    {cycles, palette} = Enum.map_reduce(cycles, world.palette, &advance(&1, &2, jiffies))
    %{world | cycles: cycles, palette: palette}
  end

  @doc "Changes the delay of cycle `id`."
  @spec set_cycle_delay(World.t(), integer(), integer()) :: World.t()
  def set_cycle_delay(world, id, delay) do
    cycles =
      Enum.map(world.cycles, fn entry ->
        if entry.cycle.id == id, do: put_in(entry.cycle.delay, delay), else: entry
      end)

    %{world | cycles: cycles}
  end

  defp advance(%{cycle: %Cycle{delay: 0}} = entry, palette, _jiffies), do: {entry, palette}

  defp advance(%{cycle: %Cycle{first: first, last: last}} = entry, palette, _jiffies)
       when first > last, do: {entry, palette}

  defp advance(%{cycle: cycle, counter: counter} = entry, palette, jiffies) do
    counter = counter + jiffies

    if counter >= cycle.delay do
      {%{entry | counter: rem(counter, cycle.delay)},
       rotate(palette, cycle.first, cycle.last, (cycle.flags &&& 2) == 0)}
    else
      {%{entry | counter: counter}, palette}
    end
  end

  defp rotate(palette, first, last, forward) do
    range = binary_part(palette, first * 3, (last - first + 1) * 3)
    count = byte_size(range)

    rotated =
      if forward,
        do: binary_part(range, count - 3, 3) <> binary_part(range, 0, count - 3),
        else: binary_part(range, 3, count - 3) <> binary_part(range, 0, 3)

    binary_part(palette, 0, first * 3) <>
      rotated <> binary_part(palette, (last + 1) * 3, byte_size(palette) - (last + 1) * 3)
  end

  defp put_rgb(palette, index, rgb) do
    binary_part(palette, 0, index * 3) <>
      rgb <> binary_part(palette, index * 3 + 3, byte_size(palette) - index * 3 - 3)
  end

  defp scaled(channel, part), do: clamp(div(channel * part, 0xFF))

  defp clamp(value), do: value |> max(0) |> min(255)
end
