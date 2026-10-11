defmodule MonkeyXland.Scumm.Room.Box do
  @moduledoc """
  A walk box from `BOXD`: four corners (upper left, upper right, lower right, lower
  left), the box's mask and flags bytes, and its scale (a percentage, or with bit 15 set
  the low bits name a scale slot).
  """

  @enforce_keys [:upper_left, :upper_right, :lower_right, :lower_left, :mask, :flags, :scale]
  defstruct @enforce_keys

  @type point :: {integer(), integer()}
  @type t :: %__MODULE__{
          upper_left: point(),
          upper_right: point(),
          lower_right: point(),
          lower_left: point(),
          mask: byte(),
          flags: byte(),
          scale: non_neg_integer()
        }

  @doc "Parses a `BOXD` body: a little-endian 16-bit count, then 20 bytes per box."
  @spec parse_all(binary()) :: [t()]
  def parse_all(<<count::little-16, boxes::binary>>) do
    for <<box::binary-20 <- binary_part(boxes, 0, min(count * 20, byte_size(boxes)))>>,
      do: parse(box)
  end

  def parse_all(_body), do: []

  defp parse(
         <<ulx::little-signed-16, uly::little-signed-16, urx::little-signed-16,
           ury::little-signed-16, lrx::little-signed-16, lry::little-signed-16,
           llx::little-signed-16, lly::little-signed-16, mask, flags, scale::little-16>>
       ) do
    %__MODULE__{
      upper_left: {ulx, uly},
      upper_right: {urx, ury},
      lower_right: {lrx, lry},
      lower_left: {llx, lly},
      mask: mask,
      flags: flags,
      scale: scale
    }
  end
end
