defmodule MonkeyXland.Scumm.Charset.Glyph do
  @moduledoc """
  One character of a font: `width × height` colour numbers, row by row, one byte each.
  `0` is transparent, `1` the text colour, other numbers index the font's colours.
  `x` and `y` shift the picture from the pen position; the pen then moves right by
  `width + x`.
  """

  @enforce_keys [:width, :height, :x, :y, :pixels]
  defstruct @enforce_keys

  @type t :: %__MODULE__{
          width: byte(),
          height: byte(),
          x: integer(),
          y: integer(),
          pixels: binary()
        }
end
