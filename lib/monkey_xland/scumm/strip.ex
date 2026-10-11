defmodule MonkeyXland.Scumm.Strip do
  @moduledoc """
  Decodes one 8-pixel-wide strip of a SCUMM v5 `SMAP` image.

  A strip starts with its codec byte:

  | codec | method | order | transparent |
  |---|---|---|---|
  | `0x01` | uncompressed | rows | no |
  | `0x0E`–`0x12` | basic | columns | no |
  | `0x18`–`0x1C` | basic | rows | no |
  | `0x22`–`0x26` | basic | columns | yes |
  | `0x2C`–`0x30` | basic | rows | yes |
  | `0x40`–`0x44`, `0x68`–`0x6C` | major/minor | rows | no |
  | `0x54`–`0x58`, `0x7C`–`0x80` | major/minor | rows | yes |

  For the compressed codecs, the codec's distance from the start of its range plus 4 is
  the number of bits a new colour is read with.

  Basic: after each pixel one bit `0` repeats the colour; `10` reads a new colour and
  resets the step to `-1`; `110` adds the step; `111` negates the step, then adds it.

  Major/minor: after each pixel one bit `0` repeats the colour; `10` reads a new colour;
  `11` reads three bits `d`: unless `d` is 4 the colour changes by `d - 4`; when `d` is 4,
  eight more bits give a run length `n` (0 meaning 256) and `n` pixels of the colour are
  written before the next command.

  The result is `8 × height` palette indices, row by row, and for transparent codecs a
  mask with `1` for each pixel that is drawn and `0` for pixels of the transparent colour.
  """

  import Bitwise

  alias MonkeyXland.Scumm.BitReader

  @type order :: :rows | :columns
  @type method ::
          :raw
          | {:basic, order(), shift :: 4..8, transparent? :: boolean()}
          | {:major_minor, shift :: 4..8, transparent? :: boolean()}
  @type decoded :: %{pixels: binary(), mask: binary() | nil}

  @width 8

  @doc "Returns how a codec byte is decoded."
  @spec method(byte()) :: {:ok, method()} | {:error, {:unknown_codec, byte()}}
  def method(0x01), do: {:ok, :raw}
  def method(code) when code in 0x0E..0x12, do: {:ok, {:basic, :columns, code - 0x0A, false}}
  def method(code) when code in 0x18..0x1C, do: {:ok, {:basic, :rows, code - 0x14, false}}
  def method(code) when code in 0x22..0x26, do: {:ok, {:basic, :columns, code - 0x1E, true}}
  def method(code) when code in 0x2C..0x30, do: {:ok, {:basic, :rows, code - 0x28, true}}
  def method(code) when code in 0x40..0x44, do: {:ok, {:major_minor, code - 0x3C, false}}
  def method(code) when code in 0x54..0x58, do: {:ok, {:major_minor, code - 0x50, true}}
  def method(code) when code in 0x68..0x6C, do: {:ok, {:major_minor, code - 0x64, false}}
  def method(code) when code in 0x7C..0x80, do: {:ok, {:major_minor, code - 0x78, true}}
  def method(code), do: {:error, {:unknown_codec, code}}

  @doc """
  Decodes a strip (codec byte first) `height` pixels tall. `transparent` is the room's
  transparent colour, used by the transparent codecs.
  """
  @spec decode(binary(), pos_integer(), byte()) ::
          {:ok, decoded()} | {:error, {:unknown_codec, byte()} | :empty}
  def decode(<<code, data::binary>>, height, transparent) do
    with {:ok, method} <- method(code) do
      {:ok, run(method, data, height, transparent)}
    end
  end

  def decode(<<>>, _height, _transparent), do: {:error, :empty}

  defp run(:raw, data, height, _transparent) do
    count = @width * height
    %{pixels: pad(binary_part(data, 0, min(count, byte_size(data))), count), mask: nil}
  end

  defp run({:basic, order, shift, transparent?}, <<color, data::binary>>, height, transparent) do
    @width
    |> Kernel.*(height)
    |> basic(color, -1, shift, BitReader.new(data))
    |> arrange(order, height)
    |> with_mask(transparent?, transparent)
  end

  defp run({:major_minor, shift, transparent?}, <<color, data::binary>>, height, transparent) do
    @width
    |> Kernel.*(height)
    |> major_minor(color, shift, BitReader.new(data))
    |> with_mask(transparent?, transparent)
  end

  defp run(_method, <<>>, height, _transparent),
    do: %{pixels: :binary.copy(<<0>>, @width * height), mask: nil}

  defp basic(count, color, step, shift, reader),
    do: basic_loop(count - 1, color, step, shift, reader, [color])

  defp basic_loop(0, _color, _step, _shift, _reader, acc), do: finish(acc)

  defp basic_loop(left, color, step, shift, reader, acc) do
    {color, step, reader} = basic_command(color, step, shift, reader)
    basic_loop(left - 1, color, step, shift, reader, [color | acc])
  end

  defp basic_command(color, step, shift, reader) do
    basic_repeat_or_change(BitReader.bit(reader), color, step, shift)
  end

  defp basic_repeat_or_change({0, reader}, color, step, _shift), do: {color, step, reader}

  defp basic_repeat_or_change({1, reader}, color, step, shift) do
    reader |> BitReader.bit() |> basic_change(color, step, shift)
  end

  defp basic_change({0, reader}, _color, _step, shift) do
    {color, reader} = BitReader.read(reader, shift)
    {color, -1, reader}
  end

  defp basic_change({1, reader}, color, step, _shift) do
    reader |> BitReader.bit() |> basic_step(color, step)
  end

  defp basic_step({0, reader}, color, step), do: {color + step &&& 0xFF, step, reader}
  defp basic_step({1, reader}, color, step), do: {color - step &&& 0xFF, -step, reader}

  defp major_minor(count, color, shift, reader),
    do: major_minor_loop(count - 1, color, shift, reader, [color])

  defp major_minor_loop(left, _color, _shift, _reader, acc) when left <= 0,
    do: acc |> Enum.drop(-left) |> finish()

  defp major_minor_loop(left, color, shift, reader, acc) do
    reader
    |> BitReader.bit()
    |> major_minor_command(left, color, shift, acc)
  end

  defp major_minor_command({0, reader}, left, color, shift, acc),
    do: major_minor_loop(left - 1, color, shift, reader, [color | acc])

  defp major_minor_command({1, reader}, left, color, shift, acc) do
    reader |> BitReader.bit() |> major_minor_change(left, color, shift, acc)
  end

  defp major_minor_change({0, reader}, left, _color, shift, acc) do
    {color, reader} = BitReader.read(reader, shift)
    major_minor_loop(left - 1, color, shift, reader, [color | acc])
  end

  defp major_minor_change({1, reader}, left, color, shift, acc) do
    {delta, reader} = BitReader.read(reader, 3)
    major_minor_delta(delta, reader, left, color, shift, acc)
  end

  defp major_minor_delta(4, reader, left, color, shift, acc) do
    {length, reader} = BitReader.read(reader, 8)
    length = run_length(length)
    major_minor_loop(left - length, color, shift, reader, repeat(color, length, acc))
  end

  defp major_minor_delta(delta, reader, left, color, shift, acc) do
    color = color + delta - 4 &&& 0xFF
    major_minor_loop(left - 1, color, shift, reader, [color | acc])
  end

  defp run_length(0), do: 256
  defp run_length(length), do: length

  defp repeat(_color, 0, acc), do: acc
  defp repeat(color, count, acc), do: repeat(color, count - 1, [color | acc])

  defp finish(reversed), do: reversed |> Enum.reverse() |> :binary.list_to_bin()

  defp arrange(pixels, :rows, _height), do: pixels

  defp arrange(pixels, :columns, height) do
    for y <- 0..(height - 1), x <- 0..(@width - 1), into: <<>> do
      <<:binary.at(pixels, x * height + y)>>
    end
  end

  defp with_mask(pixels, false, _transparent), do: %{pixels: pixels, mask: nil}

  defp with_mask(pixels, true, transparent) do
    %{
      pixels: pixels,
      mask: for(<<pixel <- pixels>>, into: <<>>, do: <<mask_bit(pixel, transparent)>>)
    }
  end

  defp mask_bit(pixel, pixel), do: 0
  defp mask_bit(_pixel, _transparent), do: 1

  defp pad(bytes, count) when byte_size(bytes) >= count, do: bytes
  defp pad(bytes, count), do: bytes <> :binary.copy(<<0>>, count - byte_size(bytes))
end
