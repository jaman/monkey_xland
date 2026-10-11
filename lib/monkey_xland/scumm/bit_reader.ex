defmodule MonkeyXland.Scumm.BitReader do
  @moduledoc """
  Reads bits from a byte stream lowest bit first, as SCUMM's strip codecs store them.

  A reader is `{bits, count, rest}`: the `count` buffered bits in `bits`, and the bytes
  not yet consumed. Reading past the end yields zero bits.

      reader = MonkeyXland.Scumm.BitReader.new(<<0b1011_0101>>)
      {0b101, reader} = MonkeyXland.Scumm.BitReader.read(reader, 3)
  """

  import Bitwise

  @type t :: {non_neg_integer(), non_neg_integer(), binary()}

  @doc "Starts reading `bytes`."
  @spec new(binary()) :: t()
  def new(bytes), do: {0, 0, bytes}

  @doc "Reads `count` bits; the first bit read becomes bit 0 of the result."
  @spec read(t(), non_neg_integer()) :: {non_neg_integer(), t()}
  def read(reader, count) do
    {bits, available, rest} = fill(reader, count)
    {bits &&& (1 <<< count) - 1, {bits >>> count, available - count, rest}}
  end

  @doc "Reads one bit."
  @spec bit(t()) :: {0 | 1, t()}
  def bit(reader), do: read(reader, 1)

  defp fill({_bits, available, _rest} = reader, count) when available >= count, do: reader

  defp fill({bits, available, <<byte, rest::binary>>}, count),
    do: fill({bits ||| byte <<< available, available + 8, rest}, count)

  defp fill({bits, _available, <<>>}, count), do: {bits, count, <<>>}
end
