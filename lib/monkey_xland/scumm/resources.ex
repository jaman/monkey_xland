defmodule MonkeyXland.Scumm.Resources do
  @moduledoc """
  The SCUMM v5 resource file (`.001`), decrypted and held in memory, with the room
  offsets from its `LOFF` block.

  `room_offsets` maps a room number to the file position of its `ROOM` block; that block
  sits at the start of the room's `LFLF`, and the index's directory offsets count from it.

      {:ok, resources} = MonkeyXland.Scumm.Resources.parse(MonkeyXland.Scumm.Block.decrypt(bytes))
      {:ok, room_block} = MonkeyXland.Scumm.Resources.room(resources, 33)
      {:ok, script} = MonkeyXland.Scumm.Resources.fetch(resources, index, :script, 1)
  """

  alias MonkeyXland.Scumm.{Block, Index}

  @enforce_keys [:data, :room_offsets]
  defstruct [:data, :room_offsets]

  @type t :: %__MODULE__{data: binary(), room_offsets: %{non_neg_integer() => non_neg_integer()}}
  @type error :: {:no_room, non_neg_integer()} | {:not_found, Index.kind(), non_neg_integer()}

  @kind_tags %{script: "SCRP", sound: "SOUN", costume: "COST", charset: "CHAR"}

  @doc "Parses a decrypted `.001` file."
  @spec parse(binary()) :: {:ok, t()} | {:error, :not_lecf | :no_loff}
  def parse(<<"LECF", _length::32, body::binary>> = data) do
    body |> Block.find("LOFF") |> with_offsets(data)
  end

  def parse(_data), do: {:error, :not_lecf}

  @doc "Returns the room numbers present in the file, in ascending order."
  @spec rooms(t()) :: [non_neg_integer()]
  def rooms(%__MODULE__{room_offsets: offsets}), do: offsets |> Map.keys() |> Enum.sort()

  @doc "Returns the body of room `number`'s `LFLF` block: its `ROOM` and the resources after it."
  @spec lflf(t(), non_neg_integer()) :: {:ok, binary()} | {:error, error()}
  def lflf(%__MODULE__{} = resources, number) do
    with {:ok, room_at} <- room_offset(resources, number),
         {:ok, {"LFLF", body}} <- block_at(resources.data, room_at - 8) do
      {:ok, body}
    else
      _other -> {:error, {:no_room, number}}
    end
  end

  @doc "Returns the body of room `number`'s `ROOM` block."
  @spec room(t(), non_neg_integer()) :: {:ok, binary()} | {:error, error()}
  def room(%__MODULE__{} = resources, number) do
    with {:ok, room_at} <- room_offset(resources, number),
         {:ok, {"ROOM", body}} <- block_at(resources.data, room_at) do
      {:ok, body}
    else
      _other -> {:error, {:no_room, number}}
    end
  end

  @doc """
  Returns the body of a script (`SCRP`), sound (`SOUN`), costume (`COST`) or charset
  (`CHAR`) block, found through the index's directory.
  """
  @spec fetch(t(), Index.t(), Index.kind(), non_neg_integer()) ::
          {:ok, binary()} | {:error, error()}
  def fetch(%__MODULE__{} = resources, %Index{} = index, kind, number) do
    tag = Map.fetch!(@kind_tags, kind)

    with {:ok, {room, offset}} <- Index.locate(index, kind, number),
         {:ok, room_at} <- room_offset(resources, room),
         {:ok, {^tag, body}} <- block_at(resources.data, room_at + offset) do
      {:ok, body}
    else
      _other -> {:error, {:not_found, kind, number}}
    end
  end

  defp with_offsets({:ok, <<count, entries::binary>>}, data) do
    offsets =
      for <<room, offset::little-32 <- binary_part(entries, 0, count * 5)>>,
        into: %{},
        do: {room, offset}

    {:ok, %__MODULE__{data: data, room_offsets: offsets}}
  end

  defp with_offsets(:error, _data), do: {:error, :no_loff}

  defp room_offset(%__MODULE__{room_offsets: offsets}, number) do
    offsets |> Map.fetch(number) |> found_room(number)
  end

  defp found_room({:ok, offset}, _number), do: {:ok, offset}
  defp found_room(:error, number), do: {:error, {:no_room, number}}

  defp block_at(data, position) when position >= 0 and position < byte_size(data) do
    data |> binary_part(position, byte_size(data) - position) |> Block.read()
  end

  defp block_at(_data, _position), do: :error
end
