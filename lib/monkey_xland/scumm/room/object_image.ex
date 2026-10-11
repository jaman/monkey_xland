defmodule MonkeyXland.Scumm.Room.ObjectImage do
  @moduledoc """
  An object's pictures from `OBIM`: its position and size in room pixels, and one
  picture per state (`IM01` is state 1, `IM02` state 2, …), each with its own z-planes.

  `IMHD` is the object number, the number of states, the number of z-planes, a flags
  byte, an unused byte, then x, y, width and height, all little-endian 16-bit words.
  """

  alias MonkeyXland.Scumm.{Block, Bomp, Image, Smap, ZPlane}

  @enforce_keys [:number, :x, :y, :width, :height, :flags, :states]
  defstruct @enforce_keys

  @type state :: %{image: Image.t(), z_planes: [ZPlane.t()]}
  @type t :: %__MODULE__{
          number: non_neg_integer(),
          x: non_neg_integer(),
          y: non_neg_integer(),
          width: non_neg_integer(),
          height: non_neg_integer(),
          flags: byte(),
          states: [state()]
        }

  @doc "Parses an `OBIM` body; `transparent` is the room's transparent colour."
  @spec parse(binary(), byte()) :: {:ok, t()} | {:error, term()}
  def parse(body, transparent) do
    children = Block.children(body)

    with {:ok, header} <- Block.find(children, "IMHD"),
         {:ok, image} <- header(header),
         {:ok, states} <- states(children, image, transparent) do
      {:ok, %{image | states: states}}
    end
  end

  defp header(
         <<number::little-16, _states::little-16, _planes::little-16, flags, _unused,
           x::little-16, y::little-16, width::little-16, height::little-16, _rest::binary>>
       ) do
    {:ok,
     %__MODULE__{
       number: number,
       x: x,
       y: y,
       width: width,
       height: height,
       flags: flags,
       states: []
     }}
  end

  defp header(_bytes), do: {:error, :bad_imhd}

  defp states(children, image, transparent) do
    children
    |> Enum.filter(fn {tag, _body} -> state_tag?(tag) end)
    |> Enum.reduce_while({:ok, []}, fn {_tag, body}, {:ok, acc} ->
      body |> state(image, transparent) |> collect(acc)
    end)
    |> reversed()
  end

  defp state_tag?(<<"IM", a, b>>) when a in ?0..?9 or a in ?A..?F, do: b in ?0..?9 or b in ?A..?F
  defp state_tag?(_tag), do: false

  defp state(body, %__MODULE__{width: width, height: height}, transparent) do
    children = Block.children(body)

    with {:ok, picture} <- picture(children, width, height, transparent) do
      {:ok, %{image: picture, z_planes: z_planes(children, width, height)}}
    end
  end

  defp picture(children, width, height, transparent) do
    picture_block(
      Block.find(children, "SMAP"),
      Block.find(children, "BOMP"),
      width,
      height,
      transparent
    )
  end

  defp picture_block({:ok, smap}, _bomp, width, height, transparent),
    do: Smap.decode(smap, width, height, transparent)

  defp picture_block(:error, {:ok, bomp}, _width, _height, transparent),
    do: Bomp.decode(bomp, transparent)

  defp picture_block(:error, :error, _width, _height, _transparent), do: {:error, :no_picture}

  defp z_planes(children, width, height) do
    for {<<"ZP", _number::binary-2>>, body} <- children, do: ZPlane.decode(body, width, height)
  end

  defp collect({:ok, state}, acc), do: {:cont, {:ok, [state | acc]}}
  defp collect({:error, reason}, _acc), do: {:halt, {:error, reason}}

  defp reversed({:ok, states}), do: {:ok, Enum.reverse(states)}
  defp reversed(error), do: error
end
