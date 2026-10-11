defmodule MonkeyXland.Scumm.Room.Object do
  @moduledoc """
  A room object from `OBCD`, with its pictures from the matching `OBIM` when it has any.

  Position and size are in room pixels. `parent` is the 1-based position, among the
  room's objects in file order, of the object this one is drawn with (0 for none), and
  `parent_state` the state that parent must be in. `walk_x`/`walk_y` is where an actor
  stands to use it and `actor_dir` the direction the actor then faces. `name` is the raw
  `OBNA` text; `@` characters in it are padding that reserves room for a longer name.

  `script` is the `VERB` block body. `verbs` maps a verb number to the position in
  `script` where that verb's code starts; verb `0xFF` is the default for verbs not
  listed.

  `CDHD` is the object number (little-endian 16-bit); x, y, width and height bytes in
  units of 8 pixels; a flags byte; the parent byte; signed little-endian 16-bit walk x and
  walk y; and the actor direction byte. A flags byte of `0x80` means parent state 1;
  otherwise its low four bits are the parent state.
  """

  import Bitwise

  alias MonkeyXland.Scumm.Block
  alias MonkeyXland.Scumm.Room.ObjectImage

  @enforce_keys [
    :number,
    :name,
    :x,
    :y,
    :width,
    :height,
    :flags,
    :parent,
    :parent_state,
    :walk_x,
    :walk_y,
    :actor_dir,
    :verbs,
    :script,
    :image
  ]
  defstruct @enforce_keys

  @type t :: %__MODULE__{
          number: non_neg_integer(),
          name: binary(),
          x: non_neg_integer(),
          y: non_neg_integer(),
          width: non_neg_integer(),
          height: non_neg_integer(),
          flags: byte(),
          parent: byte(),
          parent_state: byte(),
          walk_x: integer(),
          walk_y: integer(),
          actor_dir: byte(),
          verbs: %{byte() => non_neg_integer()},
          script: binary(),
          image: ObjectImage.t() | nil
        }

  @block_header 8

  @doc "Parses an `OBCD` body; `image` is the object's `ObjectImage` or `nil`."
  @spec parse(binary(), ObjectImage.t() | nil) :: {:ok, t()} | {:error, :bad_obcd}
  def parse(body, image) do
    children = Block.positioned(body)

    with {_tag, _at, header} <- List.keyfind(children, "CDHD", 0),
         {:ok, object} <- header(header) do
      {:ok, %{object | image: image, name: name(children)} |> with_verbs(children)}
    else
      _other -> {:error, :bad_obcd}
    end
  end

  @doc "Reads just the object number from an `OBCD` body."
  @spec number(binary()) :: {:ok, non_neg_integer()} | :error
  def number(body) do
    with {:ok, <<number::little-16, _rest::binary>>} <- Block.find(body, "CDHD") do
      {:ok, number}
    end
  end

  defp header(
         <<number::little-16, x, y, width, height, flags, parent, walk_x::little-signed-16,
           walk_y::little-signed-16, actor_dir, _rest::binary>>
       ) do
    {:ok,
     %__MODULE__{
       number: number,
       name: "",
       x: x * 8,
       y: y * 8,
       width: width * 8,
       height: height * 8,
       flags: flags,
       parent: parent,
       parent_state: parent_state(flags),
       walk_x: walk_x,
       walk_y: walk_y,
       actor_dir: actor_dir,
       verbs: %{},
       script: <<>>,
       image: nil
     }}
  end

  defp header(_bytes), do: :error

  defp parent_state(0x80), do: 1
  defp parent_state(flags), do: flags &&& 0x0F

  defp name(children) do
    children |> List.keyfind("OBNA", 0) |> object_name()
  end

  defp object_name({_tag, _at, body}), do: body |> :binary.split(<<0>>) |> hd()
  defp object_name(nil), do: ""

  defp with_verbs(object, children) do
    children |> List.keyfind("VERB", 0) |> verb_table(object)
  end

  defp verb_table({_tag, _at, body}, object) do
    %{object | script: body, verbs: entries(body, @block_header, %{})}
  end

  defp verb_table(nil, object), do: object

  defp entries(<<verb, offset::little-16, rest::binary>>, base, acc) when verb != 0,
    do: entries(rest, base, Map.put(acc, verb, offset - base))

  defp entries(_rest, _base, acc), do: acc
end
