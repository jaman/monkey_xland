defmodule MonkeyXland.Xact.WaveBank do
  @moduledoc """
  An XACT wave bank (`.xwb`, header version 43): its entries, their names, formats,
  lengths, and where their audio bytes are. The audio itself is read on demand.

  The header is `WBND`, the tool version, the header version, and five segments as
  little-endian offset and length pairs: bank data, entry metadata, seek tables, entry
  names and wave data. Bank data holds the flags, the entry count, the bank's name (64
  bytes) and the sizes of a metadata and a name entry. An entry's metadata is six words:
  flags in the low 4 bits and the length in samples in the rest, the format, the
  offset (into the wave data) and length of its bytes, and its loop start and length.

  A format word is, from the low bit: the codec in 2 bits (0 PCM, 1 XMA, 2 ADPCM,
  3 WMA), the channel count in 3, the sample rate in 18, the block-align byte in 8, and
  1 bit set for 16-bit samples. For WMA, the block-align byte's low 5 bits pick the
  packet size and its high 3 bits the average bytes per second from fixed tables.

      {:ok, bank} = MonkeyXland.Xact.WaveBank.open("audio/MusicOriginal.xwb")
      {:ok, bytes} = MonkeyXland.Xact.WaveBank.read(bank, MonkeyXland.Xact.WaveBank.entry(bank, "track22"))
  """

  import Bitwise

  @enforce_keys [:path, :name, :entries, :data_offset]
  defstruct @enforce_keys

  @type codec :: :pcm | :xma | :adpcm | :wma
  @type entry :: %{
          index: non_neg_integer(),
          name: String.t() | nil,
          codec: codec(),
          channels: pos_integer(),
          rate: pos_integer(),
          block_align: non_neg_integer(),
          bytes_per_second: non_neg_integer() | nil,
          bits: 8 | 16,
          samples: non_neg_integer(),
          offset: non_neg_integer(),
          length: non_neg_integer(),
          seek: [non_neg_integer()]
        }
  @type t :: %__MODULE__{
          path: Path.t(),
          name: String.t(),
          entries: [entry()],
          data_offset: non_neg_integer()
        }

  @codecs {:pcm, :xma, :adpcm, :wma}
  @wma_block_align {929, 1487, 1280, 2230, 8917, 8192, 4459, 5945, 2304, 1536, 1485, 1008, 2731,
                    4096, 6827, 5462, 1280}
  @wma_bytes_per_second {12_000, 24_000, 4_000, 6_000, 8_000, 20_000, 2_500}

  @doc "Reads a wave bank's header, entries and names."
  @spec open(Path.t()) :: {:ok, t()} | {:error, term()}
  def open(path) do
    with {:ok, io} <- File.open(path, [:read, :binary]),
         {:ok, header} <- pread(io, 0, 0x34),
         {:ok, segments} <- segments(header),
         {:ok, bank} <- read_bank(io, segments) do
      File.close(io)
      {:ok, %{bank | path: path}}
    end
  end

  @doc "The entry named `name`, or `nil`."
  @spec entry(t(), String.t()) :: entry() | nil
  def entry(%__MODULE__{entries: entries}, name), do: Enum.find(entries, &(&1.name == name))

  @doc "An entry's length in seconds."
  @spec seconds(entry()) :: float()
  def seconds(%{samples: samples, rate: rate}), do: samples / rate

  @doc "An entry's audio bytes, as stored."
  @spec read(t(), entry()) :: {:ok, binary()} | {:error, term()}
  def read(%__MODULE__{path: path, data_offset: data_offset}, %{offset: offset, length: length}) do
    with {:ok, io} <- File.open(path, [:read, :binary]) do
      result = pread(io, data_offset + offset, length)
      File.close(io)
      result
    end
  end

  defp pread(io, position, length) do
    case :file.pread(io, position, length) do
      {:ok, bytes} when byte_size(bytes) == length -> {:ok, bytes}
      {:ok, _short} -> {:error, :truncated}
      :eof -> {:error, :truncated}
      {:error, reason} -> {:error, reason}
    end
  end

  defp segments(<<"WBND", _tool::little-32, 43::little-32, rest::binary-40>>) do
    {:ok, for(<<offset::little-32, length::little-32 <- rest>>, do: {offset, length})}
  end

  defp segments(_header), do: {:error, :not_a_version_43_wave_bank}

  defp read_bank(io, [
         {bank_at, bank_length},
         {meta_at, _meta_length},
         {seek_at, seek_length},
         {names_at, _names_length},
         {data_at, _data_length}
       ]) do
    with {:ok,
          <<_flags::little-32, count::little-32, name::binary-64, meta_size::little-32,
            name_size::little-32, _rest::binary>>} <- pread(io, bank_at, bank_length),
         {:ok, metadata} <- pread(io, meta_at, count * meta_size),
         {:ok, names} <- names(io, names_at, count, name_size),
         {:ok, seek} <- seek_tables(io, seek_at, seek_length, count) do
      entries =
        for(
          {raw, index} <- Enum.with_index(chunks(metadata, meta_size)),
          do: parse_entry(raw, index)
        )
        |> Enum.zip(names)
        |> Enum.zip(seek)
        |> Enum.map(fn {{entry, entry_name}, table} ->
          %{entry | name: entry_name, seek: table}
        end)

      {:ok, %__MODULE__{path: nil, name: c_string(name), entries: entries, data_offset: data_at}}
    end
  end

  defp chunks(bytes, size), do: for(<<chunk::binary-size(^size) <- bytes>>, do: chunk)

  defp names(_io, 0, count, _size), do: {:ok, List.duplicate(nil, count)}

  defp names(io, at, count, size) do
    with {:ok, bytes} <- pread(io, at, count * size),
         do: {:ok, Enum.map(chunks(bytes, size), &c_string/1)}
  end

  defp seek_tables(_io, _at, 0, count), do: {:ok, List.duplicate([], count)}

  defp seek_tables(io, at, length, count) do
    with {:ok, bytes} <- pread(io, at, length) do
      <<offsets::binary-size(^count * 4), tables::binary>> = bytes
      {:ok, for(<<offset::little-32 <- offsets>>, do: seek_table(tables, offset))}
    end
  end

  defp seek_table(tables, offset) when offset + 4 <= byte_size(tables) do
    <<_skip::binary-size(^offset), count::little-32, rest::binary>> = tables
    for <<value::little-32 <- binary_part(rest, 0, min(count * 4, byte_size(rest)))>>, do: value
  end

  defp seek_table(_tables, _offset), do: []

  defp parse_entry(
         <<flags_duration::little-32, format::little-32, offset::little-32, length::little-32,
           _loop_start::little-32, _loop_length::little-32, _rest::binary>>,
         index
       ) do
    codec = elem(@codecs, format &&& 0x3)
    block_align = format >>> 23 &&& 0xFF

    %{
      index: index,
      name: nil,
      codec: codec,
      channels: format >>> 2 &&& 0x7,
      rate: format >>> 5 &&& 0x3FFFF,
      block_align: block_align(codec, block_align),
      bytes_per_second: bytes_per_second(codec, block_align),
      bits: if((format >>> 31 &&& 1) == 1, do: 16, else: 8),
      samples: flags_duration >>> 4,
      offset: offset,
      length: length,
      seek: []
    }
  end

  defp block_align(:wma, byte),
    do: elem(@wma_block_align, min(byte &&& 0x1F, tuple_size(@wma_block_align) - 1))

  defp block_align(_codec, byte), do: byte

  defp bytes_per_second(:wma, byte),
    do: elem(@wma_bytes_per_second, min(byte >>> 5, tuple_size(@wma_bytes_per_second) - 1))

  defp bytes_per_second(_codec, _byte), do: nil

  defp c_string(bytes), do: bytes |> :binary.split(<<0>>) |> hd()
end
