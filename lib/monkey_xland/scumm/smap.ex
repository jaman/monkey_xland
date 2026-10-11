defmodule MonkeyXland.Scumm.Smap do
  @moduledoc """
  Decodes an `SMAP` block body into an `MonkeyXland.Scumm.Image`.

  The body starts with one little-endian 32-bit offset per 8-pixel strip, counted from
  the start of the `SMAP` block's 8-byte header. Each strip is decoded by
  `MonkeyXland.Scumm.Strip` from its offset.
  """

  alias MonkeyXland.Scumm.{Image, Strip}

  @header 8

  @doc """
  Decodes a picture `width × height` pixels in size; `transparent` is the room's
  transparent colour.
  """
  @spec decode(binary(), non_neg_integer(), non_neg_integer(), byte()) ::
          {:ok, Image.t()} | {:error, term()}
  def decode(body, width, height, transparent) do
    body
    |> strip_starts(div(width, 8))
    |> Enum.reduce_while({:ok, []}, fn start, {:ok, acc} ->
      body
      |> binary_part(start, byte_size(body) - start)
      |> Strip.decode(height, transparent)
      |> collect(acc)
    end)
    |> to_image(height)
  end

  defp collect({:ok, decoded}, acc), do: {:cont, {:ok, [decoded | acc]}}
  defp collect({:error, reason}, _acc), do: {:halt, {:error, reason}}

  defp to_image({:ok, reversed}, height) do
    decoded = Enum.reverse(reversed)
    {:ok, Image.from_strips(Enum.map(decoded, & &1.pixels), Enum.map(decoded, & &1.mask), height)}
  end

  defp to_image(error, _height), do: error

  defp strip_starts(body, strips) when byte_size(body) >= strips * 4 do
    for <<offset::little-32 <- binary_part(body, 0, strips * 4)>>,
      do: min(max(offset - @header, 0), byte_size(body))
  end

  defp strip_starts(_body, _strips), do: []
end
