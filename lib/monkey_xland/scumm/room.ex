defmodule MonkeyXland.Scumm.Room do
  @moduledoc """
  A decoded SCUMM v5 room (`ROOM` block body).

  * `width`, `height` — the background's size in pixels (`RMHD`); `object_count` the
    number of objects it declares.
  * `palette` — 256 RGB triples, 768 bytes, 8 bits per channel (`CLUT`);
    `ega_palette` the 256-byte EGA mapping (`EPAL`) or `nil`.
  * `cycles` — palette cycles (`CYCL`); `transparent` — the colour transparent strips
    leave undrawn (`TRNS`).
  * `boxes`, `box_matrix`, `scale_slots` — walk boxes (`BOXD`), routes between them
    (`BOXM`) and actor scaling (`SCAL`).
  * `background` — the room picture (`RMIM`/`IM00`/`SMAP`); `z_planes` its masks
    (`ZP01`, `ZP02`, …).
  * `objects` — the room's objects, in file order, with their pictures.
  * `entry_script`, `exit_script` — `ENCD` and `EXCD` bytecode; `local_scripts` maps a
    local script number to its bytecode (`LSCR`); `local_script_count` is `NLSC`.

      {:ok, room} = MonkeyXland.Scumm.Room.parse(33, room_body)
  """

  alias MonkeyXland.Scumm.{Block, Image, Smap, ZPlane}
  alias MonkeyXland.Scumm.Room.{Box, BoxMatrix, Cycle, Object, ObjectImage, ScaleSlot}

  @enforce_keys [
    :number,
    :width,
    :height,
    :object_count,
    :palette,
    :ega_palette,
    :cycles,
    :transparent,
    :boxes,
    :box_matrix,
    :scale_slots,
    :background,
    :z_planes,
    :objects,
    :entry_script,
    :exit_script,
    :local_scripts,
    :local_script_count
  ]
  defstruct @enforce_keys

  @type t :: %__MODULE__{
          number: non_neg_integer(),
          width: non_neg_integer(),
          height: non_neg_integer(),
          object_count: non_neg_integer(),
          palette: binary(),
          ega_palette: binary() | nil,
          cycles: [Cycle.t()],
          transparent: byte(),
          boxes: [Box.t()],
          box_matrix: BoxMatrix.t(),
          scale_slots: [ScaleSlot.t()],
          background: Image.t(),
          z_planes: [ZPlane.t()],
          objects: [Object.t()],
          entry_script: binary(),
          exit_script: binary(),
          local_scripts: %{non_neg_integer() => binary()},
          local_script_count: non_neg_integer()
        }

  @doc "Decodes room `number` from its `ROOM` block body."
  @spec parse(non_neg_integer(), binary()) :: {:ok, t()} | {:error, term()}
  def parse(number, body) do
    children = Block.children(body)

    with {:ok, {width, height, object_count}} <- header(children),
         transparent = transparent(children),
         {:ok, rmim} <- required(children, "RMIM"),
         {:ok, background, z_planes} <- background(rmim, width, height, transparent),
         {:ok, objects} <- objects(children, transparent) do
      {:ok,
       %__MODULE__{
         number: number,
         width: width,
         height: height,
         object_count: object_count,
         palette: optional(children, "CLUT", :binary.copy(<<0>>, 768)),
         ega_palette: optional(children, "EPAL", nil),
         cycles: children |> optional("CYCL", <<>>) |> Cycle.parse_all(),
         transparent: transparent,
         boxes: children |> optional("BOXD", <<>>) |> Box.parse_all(),
         box_matrix: children |> optional("BOXM", <<>>) |> BoxMatrix.parse(),
         scale_slots: children |> optional("SCAL", <<>>) |> ScaleSlot.parse_all(),
         background: background,
         z_planes: z_planes,
         objects: objects,
         entry_script: optional(children, "ENCD", <<>>),
         exit_script: optional(children, "EXCD", <<>>),
         local_scripts: local_scripts(children),
         local_script_count: local_script_count(children)
       }}
    end
  end

  @doc "Returns the RGB triple of palette entry `index`."
  @spec color(t(), byte()) :: {byte(), byte(), byte()}
  def color(%__MODULE__{palette: palette}, index) do
    <<red, green, blue>> = binary_part(palette, index * 3, 3)
    {red, green, blue}
  end

  defp header(children) do
    with {:ok, <<width::little-16, height::little-16, objects::little-16, _rest::binary>>} <-
           required(children, "RMHD") do
      {:ok, {width, height, objects}}
    end
  end

  defp transparent(children) do
    children |> optional("TRNS", <<0, 0>>) |> little_word()
  end

  defp little_word(<<color::little-16, _rest::binary>>), do: color
  defp little_word(_body), do: 0

  defp background(rmim, width, height, transparent) do
    with {:ok, im00} <- required(Block.children(rmim), "IM00"),
         im00_children = Block.children(im00),
         {:ok, smap} <- required(im00_children, "SMAP"),
         {:ok, image} <- Smap.decode(smap, width, height, transparent) do
      {:ok, image, z_planes(im00_children, width, height)}
    end
  end

  defp z_planes(children, width, height) do
    for {<<"ZP", _number::binary-2>>, body} <- children, do: ZPlane.decode(body, width, height)
  end

  defp objects(children, transparent) do
    with {:ok, images} <- object_images(children, transparent) do
      children
      |> Block.find_all("OBCD")
      |> Enum.reduce_while({:ok, []}, fn body, {:ok, acc} ->
        body |> object(images) |> collect(acc)
      end)
      |> reversed()
    end
  end

  defp object(body, images) do
    with {:ok, number} <- Object.number(body) do
      Object.parse(body, Map.get(images, number))
    end
  end

  defp object_images(children, transparent) do
    children
    |> Block.find_all("OBIM")
    |> Enum.reduce_while({:ok, []}, fn body, {:ok, acc} ->
      body |> ObjectImage.parse(transparent) |> collect(acc)
    end)
    |> reversed()
    |> by_number()
  end

  defp by_number({:ok, images}), do: {:ok, Map.new(images, &{&1.number, &1})}
  defp by_number(error), do: error

  defp local_scripts(children) do
    for <<number, code::binary>> <- Block.find_all(children, "LSCR"),
        into: %{},
        do: {number, code}
  end

  defp local_script_count(children) do
    children |> optional("NLSC", <<0, 0>>) |> little_word()
  end

  defp collect({:ok, value}, acc), do: {:cont, {:ok, [value | acc]}}
  defp collect({:error, reason}, _acc), do: {:halt, {:error, reason}}
  defp collect(:error, _acc), do: {:halt, {:error, :bad_object}}

  defp reversed({:ok, values}), do: {:ok, Enum.reverse(values)}
  defp reversed(error), do: error

  defp required(children, tag) do
    children |> Block.find(tag) |> present(tag)
  end

  defp present({:ok, body}, _tag), do: {:ok, body}
  defp present(:error, tag), do: {:error, {:missing_block, tag}}

  defp optional(children, tag, default) do
    children |> Block.find(tag) |> or_default(default)
  end

  defp or_default({:ok, body}, _default), do: body
  defp or_default(:error, default), do: default
end
