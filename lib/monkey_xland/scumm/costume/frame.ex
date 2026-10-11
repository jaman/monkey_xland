defmodule MonkeyXland.Scumm.Costume.Frame do
  @moduledoc """
  One picture of a costume limb.

  `pixels` holds `width × height` costume colour numbers, row by row; `0` is transparent
  and any other number is looked up in the costume's palette. `rel_x`/`rel_y` place the
  picture's top-left corner relative to the actor's position; `move_x`/`move_y` is how
  far the actor moves when this picture is shown. `redirect` is `{limb, picture}` for
  costumes whose pictures can name another limb's picture, otherwise `nil`.

  On disk a picture is little-endian 16-bit width, height, rel x, rel y, move x and
  move y (all but width and height signed), then for formats `0x60`/`0x61` two bytes of
  redirect, then the run-length pixels. Pixels run top to bottom, column after column.
  Each run byte holds the colour in its high bits and the run length in its low bits:
  four and four for 16-colour costumes, five and three for 32-colour ones. A run length
  of 0 means the next byte is the length.
  """

  import Bitwise

  @enforce_keys [:width, :height, :rel_x, :rel_y, :move_x, :move_y, :redirect, :pixels]
  defstruct @enforce_keys

  @type t :: %__MODULE__{
          width: non_neg_integer(),
          height: non_neg_integer(),
          rel_x: integer(),
          rel_y: integer(),
          move_x: integer(),
          move_y: integer(),
          redirect: {byte(), byte()} | nil,
          pixels: binary()
        }

  @doc """
  Decodes the picture at the start of `bytes` for a costume with `colors` colours (16 or
  32); `redirect?` says whether the two redirect bytes are present.
  """
  @spec decode(binary(), 16 | 32, boolean()) :: {:ok, t()} | {:error, :bad_frame}
  def decode(
        <<width::little-16, height::little-16, rel_x::little-signed-16, rel_y::little-signed-16,
          move_x::little-signed-16, move_y::little-signed-16, rest::binary>>,
        colors,
        redirect?
      )
      when width <= 1024 and height <= 1024 do
    {redirect, data} = redirect(rest, redirect?)

    {:ok,
     %__MODULE__{
       width: width,
       height: height,
       rel_x: rel_x,
       rel_y: rel_y,
       move_x: move_x,
       move_y: move_y,
       redirect: redirect,
       pixels: data |> runs(width * height, shift(colors), []) |> to_rows(width, height)
     }}
  end

  def decode(_bytes, _colors, _redirect?), do: {:error, :bad_frame}

  @doc "Decodes run-length pixel bytes into `count` colour numbers in stored (column) order."
  @spec decode_runs(binary(), non_neg_integer(), 16 | 32) :: binary()
  def decode_runs(data, count, colors), do: runs(data, count, shift(colors), [])

  defp redirect(<<limb, picture, rest::binary>>, true), do: {{limb, picture}, rest}
  defp redirect(rest, _redirect?), do: {nil, rest}

  defp shift(16), do: 4
  defp shift(32), do: 3

  defp runs(_data, left, _shift, acc) when left <= 0,
    do: acc |> Enum.reverse() |> IO.iodata_to_binary() |> trim(left)

  defp runs(<<byte, rest::binary>>, left, shift, acc) do
    color = byte >>> shift
    byte |> band((1 <<< shift) - 1) |> run(rest, color, left, shift, acc)
  end

  defp runs(<<>>, left, shift, acc), do: runs(<<>>, 0, shift, [:binary.copy(<<0>>, left) | acc])

  defp run(0, <<length, rest::binary>>, color, left, shift, acc),
    do: runs(rest, left - length, shift, [:binary.copy(<<color>>, length) | acc])

  defp run(0, <<>>, color, left, shift, acc),
    do: runs(<<>>, 0, shift, [:binary.copy(<<color>>, left) | acc])

  defp run(length, rest, color, left, shift, acc),
    do: runs(rest, left - length, shift, [:binary.copy(<<color>>, length) | acc])

  defp trim(pixels, 0), do: pixels
  defp trim(pixels, over), do: binary_part(pixels, 0, byte_size(pixels) + over)

  defp to_rows(_columns, _width, 0), do: <<>>
  defp to_rows(_columns, 0, _height), do: <<>>

  defp to_rows(columns, width, height) do
    for y <- 0..(height - 1), x <- 0..(width - 1), into: <<>> do
      <<:binary.at(columns, x * height + y)>>
    end
  end
end
