defmodule MonkeyXland.Scumm.Room.Cycle do
  @moduledoc """
  A palette cycle from `CYCL`: palette entries `first..last` rotate by one every `delay`
  jiffies (`16384 / frequency`, `0` when the frequency is `0`); bit 1 of `flags` reverses
  the direction.

  On disk each cycle is its number, two unused bytes, a big-endian 16-bit frequency, a
  big-endian 16-bit flags word and the first and last palette entries; a zero number ends
  the list.
  """

  @enforce_keys [:id, :frequency, :delay, :flags, :first, :last]
  defstruct @enforce_keys

  @type t :: %__MODULE__{
          id: pos_integer(),
          frequency: non_neg_integer(),
          delay: non_neg_integer(),
          flags: non_neg_integer(),
          first: byte(),
          last: byte()
        }

  @doc "Parses a `CYCL` body."
  @spec parse_all(binary()) :: [t()]
  def parse_all(body), do: body |> collect([]) |> Enum.reverse()

  defp collect(<<id, _unused::16, frequency::16, flags::16, first, last, rest::binary>>, acc)
       when id != 0 do
    cycle = %__MODULE__{
      id: id,
      frequency: frequency,
      delay: delay(frequency),
      flags: flags,
      first: first,
      last: last
    }

    collect(rest, [cycle | acc])
  end

  defp collect(_rest, acc), do: acc

  defp delay(0), do: 0
  defp delay(frequency), do: div(16_384, frequency)
end
