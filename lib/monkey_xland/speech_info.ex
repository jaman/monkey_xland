defmodule MonkeyXland.SpeechInfo do
  @moduledoc """
  The Special Edition's `speech.info`: which voice clip speaks which line of the game.

  The file is records of 1328 bytes: a 32-bit word, then little-endian 16-bit words for
  the room, the object or local script the line is in (0 for room and global scripts),
  the offset of its `print` — from the script's start, or for an object from the start
  of the verb's code — the page of the message (pages are split by wait codes), whether
  the player speaks it, and one more; then the line's text in five languages, 256 bytes
  each with English first, padded with spaces; then the clip's cue name in 32 bytes.

  The cue name is the clip's name in `Speech.xwb`. Several lines can share a key; the
  text tells them apart.

      {:ok, info} = MonkeyXland.SpeechInfo.read("audio/speech.info")
      MonkeyXland.SpeechInfo.find(info, {32, 200, 49, 0}, "Hello?")
      #=> "GUY_32_alley_4_1"
  """

  @enforce_keys [:by_key, :by_text]
  defstruct @enforce_keys

  @type key ::
          {room :: non_neg_integer(), number :: non_neg_integer(), offset :: non_neg_integer(),
           page :: non_neg_integer()}
  @type line :: %{key: key(), text: binary(), cue: String.t()}
  @type t :: %__MODULE__{by_key: %{key() => [line()]}, by_text: %{binary() => [line()]}}

  @record 1328

  @doc "Reads `speech.info`."
  @spec read(Path.t()) :: {:ok, t()} | {:error, term()}
  def read(path) do
    with {:ok, bytes} <- File.read(path) do
      lines = for <<record::binary-size(@record) <- bytes>>, do: line(record)

      {:ok,
       %__MODULE__{
         by_key: Enum.group_by(lines, & &1.key),
         by_text: Enum.group_by(lines, &normal(&1.text))
       }}
    end
  end

  @doc """
  The cue of the line at `key` whose text is `text`: the line with that key and text,
  the only line with that key, or else a line with that text, one in the same room
  first. `nil` when none matches, and for text with nothing but spaces.
  """
  @spec find(t(), key(), binary()) :: String.t() | nil
  def find(info, key, text), do: find_normal(info, key, normal(text))

  defp find_normal(_info, _key, ""), do: nil

  defp find_normal(
         %__MODULE__{by_key: by_key, by_text: by_text},
         {room, _number, _offset, _page} = key,
         text
       ) do
    keyed = Map.get(by_key, key, [])
    texted = Map.get(by_text, text, [])

    found =
      Enum.find(keyed, &(normal(&1.text) == text)) ||
        single(keyed) ||
        Enum.find(texted, &(elem(&1.key, 0) == room)) ||
        List.first(texted)

    found && found.cue
  end

  defp single([line]), do: line
  defp single(_lines), do: nil

  defp line(
         <<_hash::little-32, room::little-16, number::little-16, offset::little-16,
           page::little-16, _ego::little-16, _extra::little-16, english::binary-256,
           _others::binary-1024, cue::binary-32>>
       ) do
    %{
      key: {room, number, offset, page},
      text: english |> :binary.split(<<0>>) |> hd() |> String.trim_trailing(),
      cue: cue |> :binary.split(<<0>>) |> hd()
    }
  end

  defp normal(text), do: text |> String.replace(~r/\s+/, " ") |> String.trim()
end
