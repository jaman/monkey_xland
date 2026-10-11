defmodule MonkeyXland.Scumm.Index do
  @moduledoc """
  The SCUMM v5 index file (`.000`): room names, the engine's table sizes, where every
  room, script, sound, costume and charset lives, and every object's owner, state and
  classes.

  Directories map a resource number to `{room, offset}`, where `offset` counts from the
  start of that room's `ROOM` block in `.001`. Entries whose room is `0` are unused and are
  left out. `rooms` maps a room number to the disk it is on.

      {:ok, index} = MonkeyXland.Scumm.Index.parse(MonkeyXland.Scumm.Block.decrypt(bytes))
      {:ok, {room, offset}} = MonkeyXland.Scumm.Index.locate(index, :script, 1)
  """

  import Bitwise

  alias MonkeyXland.Scumm.Block

  @enforce_keys [
    :room_names,
    :maximums,
    :rooms,
    :scripts,
    :sounds,
    :costumes,
    :charsets,
    :objects
  ]
  defstruct @enforce_keys

  @type location :: {room :: non_neg_integer(), offset :: non_neg_integer()}
  @type directory :: %{non_neg_integer() => location()}
  @type kind :: :script | :sound | :costume | :charset
  @type object_entry :: %{
          owner: 0..15,
          state: 0..15,
          classes: non_neg_integer()
        }
  @type maximums :: %{
          variables: non_neg_integer(),
          unknown: non_neg_integer(),
          bit_variables: non_neg_integer(),
          local_objects: non_neg_integer(),
          new_names: non_neg_integer(),
          charsets: non_neg_integer(),
          verbs: non_neg_integer(),
          arrays: non_neg_integer(),
          inventory_objects: non_neg_integer()
        }
  @type t :: %__MODULE__{
          room_names: %{non_neg_integer() => String.t()},
          maximums: maximums(),
          rooms: %{non_neg_integer() => non_neg_integer()},
          scripts: directory(),
          sounds: directory(),
          costumes: directory(),
          charsets: directory(),
          objects: %{non_neg_integer() => object_entry()}
        }

  @doc "Parses a decrypted `.000` file."
  @spec parse(binary()) :: {:ok, t()} | {:error, {:missing_block, Block.tag()}}
  def parse(bytes) do
    blocks = Block.children(bytes)

    with {:ok, rnam} <- fetch(blocks, "RNAM"),
         {:ok, maxs} <- fetch(blocks, "MAXS"),
         {:ok, droo} <- fetch(blocks, "DROO"),
         {:ok, dscr} <- fetch(blocks, "DSCR"),
         {:ok, dsou} <- fetch(blocks, "DSOU"),
         {:ok, dcos} <- fetch(blocks, "DCOS"),
         {:ok, dchr} <- fetch(blocks, "DCHR"),
         {:ok, dobj} <- fetch(blocks, "DOBJ") do
      {:ok,
       %__MODULE__{
         room_names: room_names(rnam, %{}),
         maximums: maximums(maxs),
         rooms: room_disks(droo),
         scripts: directory(dscr),
         sounds: directory(dsou),
         costumes: directory(dcos),
         charsets: directory(dchr),
         objects: objects(dobj)
       }}
    end
  end

  @doc "Returns the `{room, offset}` of resource `number` of the given kind."
  @spec locate(t(), kind(), non_neg_integer()) :: {:ok, location()} | :error
  def locate(%__MODULE__{} = index, kind, number) do
    index |> Map.fetch!(directory_key(kind)) |> Map.fetch(number)
  end

  defp directory_key(:script), do: :scripts
  defp directory_key(:sound), do: :sounds
  defp directory_key(:costume), do: :costumes
  defp directory_key(:charset), do: :charsets

  defp fetch(blocks, tag) do
    blocks |> Block.find(tag) |> required(tag)
  end

  defp required({:ok, body}, _tag), do: {:ok, body}
  defp required(:error, tag), do: {:error, {:missing_block, tag}}

  defp room_names(<<0, _rest::binary>>, acc), do: acc

  defp room_names(<<room, name::binary-9, rest::binary>>, acc) do
    room_names(rest, Map.put(acc, room, unmask_name(name)))
  end

  defp room_names(_rest, acc), do: acc

  defp unmask_name(name) do
    for(<<byte <- name>>, into: <<>>, do: <<bxor(byte, 0xFF)>>)
    |> :binary.split(<<0>>)
    |> hd()
  end

  defp maximums(
         <<variables::little-16, unknown::little-16, bit_variables::little-16,
           local_objects::little-16, new_names::little-16, charsets::little-16, verbs::little-16,
           arrays::little-16, inventory_objects::little-16, _rest::binary>>
       ) do
    %{
      variables: variables,
      unknown: unknown,
      bit_variables: bit_variables,
      local_objects: local_objects,
      new_names: new_names,
      charsets: charsets,
      verbs: verbs,
      arrays: arrays,
      inventory_objects: inventory_objects
    }
  end

  defp room_disks(<<count::little-16, disks::binary-size(count), _rest::binary>>) do
    for {disk, room} <- disks |> :binary.bin_to_list() |> Enum.with_index(),
        disk != 0,
        into: %{},
        do: {room, disk}
  end

  defp directory(<<count::little-16, rooms::binary-size(count), rest::binary>>) do
    offsets = for <<offset::little-32 <- binary_part(rest, 0, count * 4)>>, do: offset

    for {{room, offset}, number} <-
          rooms |> :binary.bin_to_list() |> Enum.zip(offsets) |> Enum.with_index(),
        room != 0,
        into: %{},
        do: {number, {room, offset}}
  end

  defp objects(<<count::little-16, owners::binary-size(count), rest::binary>>) do
    classes = for <<class::little-32 <- binary_part(rest, 0, count * 4)>>, do: class

    for {{owner_state, class}, number} <-
          owners |> :binary.bin_to_list() |> Enum.zip(classes) |> Enum.with_index(),
        into: %{},
        do: {number, %{owner: owner_state &&& 0x0F, state: owner_state >>> 4, classes: class}}
  end
end
