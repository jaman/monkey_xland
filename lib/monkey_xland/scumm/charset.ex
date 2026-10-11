defmodule MonkeyXland.Scumm.Charset do
  @moduledoc """
  A SCUMM v5 font (`CHAR` block body).

  * `colors` — the 15 palette indices the font's colours 1 to 15 start as; a script can
    change them with `cursor_command`'s `charset_colors`,
  * `bits` — bits per pixel (1, 2 or 4),
  * `height` — the line height,
  * `glyphs` — a map from character code to `Glyph`; codes without a picture are absent.

  On disk: a 32-bit size, the version word, the 15 colour bytes, then — the position
  every glyph offset counts from — the bits per pixel, the height, a 16-bit glyph count
  and one 32-bit offset per glyph (0 for none). A glyph is its width, height, signed x
  and y offsets, then its pixels row by row, `bits` each, packed from the high bit with
  no padding between rows.

      {:ok, charset} = MonkeyXland.Scumm.Charset.parse(char_body)
  """

  alias __MODULE__.Glyph

  @enforce_keys [:colors, :bits, :height, :glyphs]
  defstruct @enforce_keys

  @type t :: %__MODULE__{
          colors: [byte()],
          bits: 1 | 2 | 4,
          height: pos_integer(),
          glyphs: %{byte() => Glyph.t()}
        }

  @base 21

  @doc "Decodes a `CHAR` block body."
  @spec parse(binary()) :: {:ok, t()} | {:error, :bad_charset}
  def parse(
        <<_size::little-32, _version::little-16, colors::binary-15, bits, height,
          count::little-16, rest::binary>> = body
      )
      when bits in [1, 2, 4] and byte_size(rest) >= count * 4 do
    offsets = for <<offset::little-32 <- binary_part(rest, 0, count * 4)>>, do: offset

    glyphs =
      for {offset, code} <- Enum.with_index(offsets), offset != 0, into: %{} do
        {code, glyph(body, @base + offset, bits)}
      end

    {:ok,
     %__MODULE__{colors: :binary.bin_to_list(colors), bits: bits, height: height, glyphs: glyphs}}
  end

  def parse(_body), do: {:error, :bad_charset}

  @doc "The width a string takes in this font, the widest of its lines."
  @spec width(t(), binary()) :: non_neg_integer()
  def width(%__MODULE__{} = charset, text) do
    text
    |> :binary.split("\n", [:global])
    |> Enum.map(&line_width(charset, &1))
    |> Enum.max(fn -> 0 end)
  end

  defp line_width(%__MODULE__{glyphs: glyphs}, line) do
    for <<code <- line>>, reduce: 0 do
      sum -> sum + advance(Map.get(glyphs, code))
    end
  end

  defp advance(nil), do: 0
  defp advance(%Glyph{width: width, x: x}), do: width + x

  defp glyph(body, at, bits) do
    <<_::binary-size(^at), width, height, x::signed, y::signed, data::binary>> = body
    %Glyph{width: width, height: height, x: x, y: y, pixels: unpack(data, width * height, bits)}
  end

  defp unpack(data, count, bits) do
    needed = div(count * bits + 7, 8)
    packed = binary_part(data, 0, min(needed, byte_size(data)))
    pixels = for <<value::size(^bits) <- packed>>, into: <<>>, do: <<value>>
    binary_part(pixels, 0, min(count, byte_size(pixels)))
  end
end
