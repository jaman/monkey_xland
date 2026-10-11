defmodule MonkeyXland.Scumm.Room.ScaleSlot do
  @moduledoc """
  One of a room's four `SCAL` slots: actors are drawn at `scale1` percent at row `y1`
  and `scale2` percent at row `y2`, interpolated between.
  """

  @enforce_keys [:scale1, :y1, :scale2, :y2]
  defstruct @enforce_keys

  @type t :: %__MODULE__{
          scale1: non_neg_integer(),
          y1: non_neg_integer(),
          scale2: non_neg_integer(),
          y2: non_neg_integer()
        }

  @doc "Parses a `SCAL` body: 8 bytes per slot, four little-endian 16-bit words."
  @spec parse_all(binary()) :: [t()]
  def parse_all(body) do
    for <<scale1::little-16, y1::little-16, scale2::little-16, y2::little-16 <- body>>,
      do: %__MODULE__{scale1: scale1, y1: y1, scale2: scale2, y2: y2}
  end
end
