defmodule MonkeyXland.Scumm.Costume do
  @moduledoc """
  A decoded SCUMM v5 costume (`COST` block body): the pictures an actor is drawn with and
  the animations that sequence them.

  * `colors` — 16 or 32; `palette` maps costume colour `n` (a list position) to a room
    palette index.
  * `mirror?` — when `true`, west-facing animations are drawn by flipping the east-facing
    pictures horizontally.
  * `limbs` — 16 lists of `Frame`s (`nil` where a picture slot is empty); limb 0 is drawn
    first.
  * `commands` — the animation command list; each entry is `{:frame, n}` (show picture
    `n` of the limb), `:sound` (play the actor's sound), `:stop`, `:start`, `:hide`,
    `:count` (add one to the actor's animation counter) or `{:command, byte}`.
  * `animations` — maps an animation number to its limbs: `{:play, first, last, loop?}`
    runs `commands` positions `first..last` for that limb; `:disable` stops the limb.
    Animation `4 × n + direction` is animation `n` facing west, east, south or north
    (direction 0, 1, 2, 3).

  On disk: the animation count minus one, the format byte (`0x58`/`0x59`: 16/32
  colours; `0x60`/`0x61`: the same with redirect bytes in each picture; bit 7 set: no
  mirroring), the palette, the command list offset, 16 limb table offsets, then one offset
  per animation. Offsets count from 6 bytes before the body. An animation is a 16-bit
  limb mask (bit 15 is limb 0); for each limb in the mask a 16-bit command position,
  `0xFFFF` for `:disable`, otherwise followed by a byte whose bit 7 means no loop and whose
  low 7 bits are the number of further commands.

      {:ok, costume} = MonkeyXland.Scumm.Costume.parse(cost_body)
  """

  import Bitwise

  alias MonkeyXland.Scumm.{Costume.Frame, Image}

  @enforce_keys [:format, :colors, :mirror?, :palette, :limbs, :commands, :animations]
  defstruct @enforce_keys

  @type command ::
          {:frame, non_neg_integer()}
          | :sound
          | :count
          | :stop
          | :start
          | :hide
          | {:command, byte()}
  @type limb_animation ::
          {:play, non_neg_integer(), non_neg_integer(), boolean()} | :disable
  @type t :: %__MODULE__{
          format: byte(),
          colors: 16 | 32,
          mirror?: boolean(),
          palette: [byte()],
          limbs: [[Frame.t() | nil]],
          commands: [command()],
          animations: %{non_neg_integer() => %{(0..15) => limb_animation()}}
        }

  @base -6
  @limbs 16

  @doc "Decodes a `COST` block body."
  @spec parse(binary()) :: {:ok, t()} | {:error, term()}
  def parse(<<last_animation, format, rest::binary>> = body) do
    colors = colors(format)
    palette_size = colors

    with <<palette::binary-size(^palette_size), commands_at::little-16,
           limb_table::binary-size(@limbs * 2), anim_table::binary>> <- rest,
         anim_offsets =
           for(<<o::little-16 <- binary_part(anim_table, 0, (last_animation + 1) * 2)>>, do: o),
         limb_offsets = for(<<o::little-16 <- limb_table>>, do: o),
         {:ok, limbs} <- limbs(body, limb_offsets, colors, redirect?(format)) do
      {:ok,
       %__MODULE__{
         format: format,
         colors: colors,
         mirror?: (format &&& 0x80) == 0,
         palette: :binary.bin_to_list(palette),
         limbs: limbs,
         commands: commands(body, commands_at, anim_offsets, limb_offsets),
         animations: animations(body, anim_offsets)
       }}
    else
      {:error, reason} -> {:error, reason}
      _other -> {:error, :bad_costume}
    end
  end

  def parse(_body), do: {:error, :bad_costume}

  @doc """
  Turns a frame into an `Image` of room palette indices, transparent where the frame has
  colour 0, flipped horizontally when `mirror` is `true`.
  """
  @spec to_image(t(), Frame.t(), boolean()) :: Image.t()
  def to_image(%__MODULE__{palette: palette}, %Frame{} = frame, mirror \\ false) do
    lookup = List.to_tuple(palette)
    rows = frame.pixels |> rows(frame.width) |> Enum.map(&flip(&1, mirror))

    %Image{
      width: frame.width,
      height: frame.height,
      pixels: for(row <- rows, <<color <- row>>, into: <<>>, do: <<elem(lookup, color)>>),
      mask: for(row <- rows, <<color <- row>>, into: <<>>, do: <<min(color, 1)>>)
    }
  end

  defp colors(format) when (format &&& 0x7F) in [0x59, 0x61], do: 32
  defp colors(_format), do: 16

  defp redirect?(format), do: (format &&& 0x7E) == 0x60

  defp rows(_pixels, 0), do: []
  defp rows(pixels, width), do: for(<<row::binary-size(^width) <- pixels>>, do: row)

  defp flip(row, false), do: row

  defp flip(row, true),
    do: row |> :binary.bin_to_list() |> Enum.reverse() |> :binary.list_to_bin()

  defp limbs(body, limb_offsets, colors, redirect?) do
    tables = limb_tables(body, limb_offsets)

    tables
    |> Enum.reduce_while({:ok, []}, fn offsets, {:ok, acc} ->
      offsets |> frames(body, colors, redirect?) |> collect(acc)
    end)
    |> reversed()
  end

  defp frames(offsets, body, colors, redirect?) do
    Enum.reduce_while(offsets, {:ok, []}, fn offset, {:ok, acc} ->
      offset |> frame(body, colors, redirect?) |> collect(acc)
    end)
    |> reversed()
  end

  defp frame(0, _body, _colors, _redirect?), do: {:ok, nil}

  defp frame(offset, body, colors, redirect?) do
    body |> from(offset) |> Frame.decode(colors, redirect?)
  end

  defp limb_tables(body, limb_offsets) do
    starts = limb_offsets |> Enum.uniq() |> Enum.sort()
    first_picture = first_picture(body, starts)

    Enum.map(limb_offsets, fn start ->
      stop = starts |> Enum.find(first_picture, &(&1 > start)) |> min(first_picture)
      count = max(div(stop - start, 2), 0)
      for <<offset::little-16 <- body |> from(start) |> binary_part(0, count * 2)>>, do: offset
    end)
  end

  defp first_picture(body, starts) do
    table_start = List.first(starts)
    scan_pictures(body, table_start, byte_size(body) - @base)
  end

  defp scan_pictures(_body, position, limit) when position >= limit, do: limit

  defp scan_pictures(body, position, limit) do
    <<offset::little-16, _rest::binary>> = from(body, position)
    scan_pictures(body, position + 2, picture_limit(offset, position, limit))
  end

  defp picture_limit(offset, position, limit) when offset > position, do: min(offset, limit)
  defp picture_limit(_offset, _position, limit), do: limit

  defp commands(body, commands_at, anim_offsets, limb_offsets) do
    stop =
      (anim_offsets ++ limb_offsets)
      |> Enum.filter(&(&1 > commands_at))
      |> Enum.min(fn -> byte_size(body) - @base end)

    body
    |> from(commands_at)
    |> binary_part(0, stop - commands_at)
    |> :binary.bin_to_list()
    |> Enum.map(&command/1)
  end

  defp command(byte) when byte < 0x78, do: {:frame, byte}
  defp command(0x78), do: :sound
  defp command(0x79), do: :stop
  defp command(0x7A), do: :start
  defp command(0x7B), do: :hide
  defp command(0x7C), do: :count
  defp command(byte), do: {:command, byte}

  defp animations(body, anim_offsets) do
    for {offset, number} <- Enum.with_index(anim_offsets), offset != 0, into: %{} do
      {number, animation(from(body, offset))}
    end
  end

  defp animation(<<mask::16-little, rest::binary>>) do
    limbs = for limb <- 0..15, (mask &&& 0x8000 >>> limb) != 0, do: limb
    limbs |> limb_animations(rest, %{})
  end

  defp limb_animations([], _rest, acc), do: acc

  defp limb_animations([limb | limbs], <<0xFFFF::16, rest::binary>>, acc),
    do: limb_animations(limbs, rest, Map.put(acc, limb, :disable))

  defp limb_animations([limb | limbs], <<first::little-16, length, rest::binary>>, acc) do
    play = {:play, first, first + (length &&& 0x7F), (length &&& 0x80) == 0}
    limb_animations(limbs, rest, Map.put(acc, limb, play))
  end

  defp limb_animations(_limbs, _rest, acc), do: acc

  defp from(body, offset) do
    position = offset + @base
    binary_part(body, position, byte_size(body) - position)
  end

  defp collect({:ok, value}, acc), do: {:cont, {:ok, [value | acc]}}
  defp collect({:error, reason}, _acc), do: {:halt, {:error, reason}}

  defp reversed({:ok, values}), do: {:ok, Enum.reverse(values)}
  defp reversed(error), do: error
end
