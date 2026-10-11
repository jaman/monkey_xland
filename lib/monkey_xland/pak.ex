defmodule MonkeyXland.Pak do
  @moduledoc """
  Reads the Special Edition's `KAPL` archive (`Monkey1.pak`) without loading it whole.

  `open/1` reads the header, the entry table and the name table; `read/2` reads one file's
  bytes with a positioned read. The archive stays open until `close/1`.

      {:ok, pak} = MonkeyXland.Pak.open(Path.join(game_dir, "Monkey1.pak"))
      {:ok, index} = MonkeyXland.Pak.read(pak, "classic/en/monkey1.000")
      :ok = MonkeyXland.Pak.close(pak)
  """

  alias MonkeyXland.Pak.Entry

  @enforce_keys [:path, :io, :data_offset, :entries]
  defstruct [:path, :io, :data_offset, :entries]

  @type t :: %__MODULE__{
          path: Path.t(),
          io: :file.io_device(),
          data_offset: non_neg_integer(),
          entries: %{String.t() => Entry.t()}
        }

  @header_size 40

  @doc "Opens the archive at `path` and reads its entry and name tables."
  @spec open(Path.t()) :: {:ok, t()} | {:error, term()}
  def open(path) do
    with {:ok, io} <- :file.open(path, [:read, :binary, :raw]),
         {:ok, header} <- pread(io, 0, @header_size),
         {:ok, layout} <- parse_header(header),
         {:ok, entry_bytes} <- pread(io, layout.entries_offset, layout.entries_size),
         {:ok, name_bytes} <- pread(io, layout.names_offset, layout.names_size) do
      {:ok,
       %__MODULE__{
         path: path,
         io: io,
         data_offset: layout.data_offset,
         entries: parse_entries(entry_bytes, name_bytes)
       }}
    end
  end

  @doc "Closes the archive."
  @spec close(t()) :: :ok | {:error, term()}
  def close(%__MODULE__{io: io}), do: :file.close(io)

  @doc "Returns every entry, sorted by name."
  @spec list(t()) :: [Entry.t()]
  def list(%__MODULE__{entries: entries}), do: entries |> Map.values() |> Enum.sort_by(& &1.name)

  @doc "Returns the entry named `name`."
  @spec fetch_entry(t(), String.t()) :: {:ok, Entry.t()} | {:error, {:not_found, String.t()}}
  def fetch_entry(%__MODULE__{entries: entries}, name) do
    entries |> Map.fetch(name) |> found_or(name)
  end

  @doc "Reads the whole file named `name`."
  @spec read(t(), String.t()) :: {:ok, binary()} | {:error, term()}
  def read(%__MODULE__{} = pak, name) do
    with {:ok, entry} <- fetch_entry(pak, name) do
      pread(pak.io, pak.data_offset + entry.position, entry.size)
    end
  end

  @doc "Reads `length` bytes starting `offset` bytes into the file named `name`."
  @spec read(t(), String.t(), non_neg_integer(), non_neg_integer()) ::
          {:ok, binary()} | {:error, term()}
  def read(%__MODULE__{} = pak, name, offset, length) do
    with {:ok, entry} <- fetch_entry(pak, name) do
      pread(pak.io, pak.data_offset + entry.position + offset, min(length, entry.size - offset))
    end
  end

  @doc "Opens the archive, reads one file and closes the archive."
  @spec read_file(Path.t(), String.t()) :: {:ok, binary()} | {:error, term()}
  def read_file(path, name) do
    with {:ok, pak} <- open(path) do
      result = read(pak, name)
      close(pak)
      result
    end
  end

  defp found_or({:ok, entry}, _name), do: {:ok, entry}
  defp found_or(:error, name), do: {:error, {:not_found, name}}

  defp parse_header(
         <<"KAPL", _version::binary-4, _index_offset::little-32, entries_offset::little-32,
           names_offset::little-32, data_offset::little-32, _index_size::little-32,
           entries_size::little-32, names_size::little-32, _data_size::little-32>>
       ) do
    {:ok,
     %{
       entries_offset: entries_offset,
       entries_size: entries_size,
       names_offset: names_offset,
       names_size: names_size,
       data_offset: data_offset
     }}
  end

  defp parse_header(_header), do: {:error, :not_kapl}

  defp parse_entries(entry_bytes, name_bytes) do
    for <<position::little-32, name_at::little-32, size::little-32, _size_again::little-32,
          compressed::little-32 <- entry_bytes>>,
        into: %{} do
      name = name_at(name_bytes, name_at)

      {name, %Entry{name: name, position: position, size: size, compressed?: compressed != 0}}
    end
  end

  defp name_at(name_bytes, at) do
    [name | _] = :binary.split(binary_part(name_bytes, at, byte_size(name_bytes) - at), <<0>>)
    name
  end

  defp pread(io, offset, length) do
    io |> :file.pread(offset, length) |> exact_read(length)
  end

  defp exact_read({:ok, bytes}, length) when byte_size(bytes) == length, do: {:ok, bytes}
  defp exact_read({:ok, _bytes}, _length), do: {:error, :short_read}
  defp exact_read(:eof, 0), do: {:ok, <<>>}
  defp exact_read(:eof, _length), do: {:error, :short_read}
  defp exact_read({:error, reason}, _length), do: {:error, reason}
end
