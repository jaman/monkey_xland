defmodule MonkeyXland.Scumm.ZPlane do
  @moduledoc """
  A z-plane mask (`ZP01`, `ZP02`, …): which pixels of a room or object image are in front
  of actors standing behind that plane.

  `bits` holds `height` rows of `width / 8` bytes; in each byte the highest bit is the
  leftmost pixel, and a set bit masks the actor.

  An encoded plane is one little-endian 16-bit offset per strip, counted from the start
  of the block's 8-byte header, `0` for an empty strip. A strip is one byte per row,
  compressed in runs: a count byte with the high bit set repeats the next byte
  `count & 0x7F` times; otherwise `count` literal bytes follow.
  """

  import Bitwise

  @enforce_keys [:width, :height, :bits]
  defstruct [:width, :height, :bits]

  @type t :: %__MODULE__{width: non_neg_integer(), height: non_neg_integer(), bits: binary()}

  @header 8

  @doc "Decodes a `ZPnn` block body for a picture `width × height` pixels in size."
  @spec decode(binary(), non_neg_integer(), non_neg_integer()) :: t()
  def decode(body, width, height) do
    strips = div(width, 8)

    columns =
      for <<offset::little-16 <- binary_part(body, 0, min(strips * 2, byte_size(body)))>>,
        do: strip(body, offset - @header, height)

    %__MODULE__{
      width: width,
      height: height,
      bits: interleave(pad_columns(columns, strips, height), height)
    }
  end

  @doc "Returns whether the pixel at `{x, y}` is set."
  @spec set?(t(), {non_neg_integer(), non_neg_integer()}) :: boolean()
  def set?(%__MODULE__{width: width, bits: bits}, {x, y}) do
    byte = :binary.at(bits, y * div(width, 8) + div(x, 8))
    (byte &&& 0x80 >>> rem(x, 8)) != 0
  end

  @doc "Decodes one strip's run-length bytes into `height` bytes."
  @spec strip(binary(), integer(), non_neg_integer()) :: binary()
  def strip(_body, start, height) when start < 0, do: :binary.copy(<<0>>, height)

  def strip(body, start, height) when start >= byte_size(body), do: :binary.copy(<<0>>, height)

  def strip(body, start, height) do
    body
    |> binary_part(start, byte_size(body) - start)
    |> runs(height, [])
    |> Enum.reverse()
    |> IO.iodata_to_binary()
    |> binary_part(0, height)
  end

  defp runs(_bytes, left, acc) when left <= 0, do: acc

  defp runs(<<count, value, rest::binary>>, left, acc) when count >= 0x80 do
    length = count &&& 0x7F
    runs(rest, left - length, [:binary.copy(<<value>>, length) | acc])
  end

  defp runs(<<count, rest::binary>>, left, acc) when byte_size(rest) >= count do
    <<literal::binary-size(^count), rest::binary>> = rest
    runs(rest, left - count, [literal | acc])
  end

  defp runs(_bytes, left, acc), do: [:binary.copy(<<0>>, left) | acc]

  defp pad_columns(columns, strips, height) do
    columns ++ List.duplicate(:binary.copy(<<0>>, height), max(strips - length(columns), 0))
  end

  defp interleave([], _height), do: <<>>

  defp interleave(columns, height) do
    for y <- 0..(height - 1)//1, column <- columns, into: <<>>, do: <<:binary.at(column, y)>>
  end
end
