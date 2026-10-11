defmodule MonkeyXland.Scumm.Bomp do
  @moduledoc """
  Decodes a `BOMP` object picture into an `MonkeyXland.Scumm.Image`.

  The body is an unused 16-bit word, the little-endian 16-bit width and height, four
  unused bytes, then one row after another: a little-endian 16-bit byte count, then that
  many bytes of runs. A run byte `code` with bit 0 set repeats the next byte
  `(code >>> 1) + 1` times; with bit 0 clear, `(code >>> 1) + 1` literal bytes follow.
  Pixels of the room's transparent colour are masked out.
  """

  import Bitwise

  alias MonkeyXland.Scumm.Image

  @doc "Decodes a `BOMP` body; `transparent` is the room's transparent colour."
  @spec decode(binary(), byte()) :: {:ok, Image.t()} | {:error, :bad_bomp}
  def decode(
        <<_unused::16, width::little-16, height::little-16, _skip::32, rows::binary>>,
        transparent
      ) do
    pixels = rows |> decode_rows(width, height, []) |> IO.iodata_to_binary()
    mask = for <<pixel <- pixels>>, into: <<>>, do: <<mask_bit(pixel, transparent)>>
    {:ok, %Image{width: width, height: height, pixels: pixels, mask: mask}}
  end

  def decode(_body, _transparent), do: {:error, :bad_bomp}

  defp decode_rows(_rows, _width, 0, acc), do: Enum.reverse(acc)

  defp decode_rows(
         <<length::little-16, row::binary-size(length), rest::binary>>,
         width,
         left,
         acc
       ),
       do: decode_rows(rest, width, left - 1, [fit(runs(row, []), width) | acc])

  defp decode_rows(_rows, width, left, acc),
    do: decode_rows(<<>>, width, 0, List.duplicate(:binary.copy(<<0>>, width), left) ++ acc)

  defp runs(<<code, value, rest::binary>>, acc) when (code &&& 1) == 1,
    do: runs(rest, [:binary.copy(<<value>>, (code >>> 1) + 1) | acc])

  defp runs(<<code, rest::binary>>, acc) when byte_size(rest) > code >>> 1 do
    count = (code >>> 1) + 1
    <<literal::binary-size(^count), rest::binary>> = rest
    runs(rest, [literal | acc])
  end

  defp runs(_rest, acc), do: acc |> Enum.reverse() |> IO.iodata_to_binary()

  defp fit(row, width) when byte_size(row) >= width, do: binary_part(row, 0, width)
  defp fit(row, width), do: row <> :binary.copy(<<0>>, width - byte_size(row))

  defp mask_bit(pixel, pixel), do: 0
  defp mask_bit(_pixel, _transparent), do: 1
end
