defmodule MonkeyXland.Scumm.Image do
  @moduledoc """
  An indexed picture: `width × height` palette indices, row by row, one byte each.

  `mask` is `nil` when every pixel is drawn, otherwise one byte per pixel, `1` where the
  pixel is drawn and `0` where whatever is underneath shows through.
  """

  @enforce_keys [:width, :height, :pixels, :mask]
  defstruct [:width, :height, :pixels, :mask]

  @type t :: %__MODULE__{
          width: non_neg_integer(),
          height: non_neg_integer(),
          pixels: binary(),
          mask: binary() | nil
        }

  @doc "Returns the palette index at `{x, y}`."
  @spec pixel(t(), {non_neg_integer(), non_neg_integer()}) :: byte()
  def pixel(%__MODULE__{width: width, pixels: pixels}, {x, y}),
    do: :binary.at(pixels, y * width + x)

  @doc "Returns whether the pixel at `{x, y}` is drawn."
  @spec opaque?(t(), {non_neg_integer(), non_neg_integer()}) :: boolean()
  def opaque?(%__MODULE__{mask: nil}, _position), do: true

  def opaque?(%__MODULE__{width: width, mask: mask}, {x, y}),
    do: :binary.at(mask, y * width + x) == 1

  @doc """
  Joins 8-pixel-wide column images, given left to right, each `height` rows of 8 bytes,
  into one picture. `masks` holds each strip's mask or `nil`.
  """
  @spec from_strips([binary()], [binary() | nil], non_neg_integer()) :: t()
  def from_strips(strips, masks, height) do
    %__MODULE__{
      width: 8 * length(strips),
      height: height,
      pixels: interleave(strips, height),
      mask: join_masks(masks, height)
    }
  end

  defp join_masks(masks, height) do
    masks
    |> Enum.all?(&is_nil/1)
    |> joined_masks(masks, height)
  end

  defp joined_masks(true, _masks, _height), do: nil

  defp joined_masks(false, masks, height) do
    masks
    |> Enum.map(fn mask -> mask || :binary.copy(<<1>>, 8 * height) end)
    |> interleave(height)
  end

  defp interleave([], _height), do: <<>>

  defp interleave(strips, height) do
    for y <- 0..(height - 1), strip <- strips, into: <<>> do
      binary_part(strip, y * 8, 8)
    end
  end
end
