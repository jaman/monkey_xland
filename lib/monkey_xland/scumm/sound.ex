defmodule MonkeyXland.Scumm.Sound do
  @moduledoc """
  A SCUMM v5 sound (`SOUN` block body), with every form it carries.

  * `{:sample, rate, pcm}` — an `SBL ` recording: unsigned 8-bit mono PCM at `rate` Hz,
  * `{:roland, midi}` — `ROL `, a Standard MIDI File for a Roland MT-32,
  * `{:adlib, midi}` — `ADL `, a Standard MIDI File for an AdLib card,
  * `{:speaker, bytes}` — `SPK `, the same for the PC speaker,
  * `{:cd, track}` — a sound with no `SOU ` block: music on the CD, as
    `%{track: n, loops: n, start: {min, sec, frame}, finish: {min, sec, frame}}`; `loops`
    is `:forever` for `0xFF`, and a finish of `{0, 0, 0}` means the end of the track.

  An `SBL ` block holds `AUhd` (whose length word counts only its three bytes) and
  `AUdt` (whose length counts its header), and `AUdt` holds Creative Voice blocks: a
  type byte and a 24-bit little-endian length, where type 1 is a rate byte
  (`1_000_000 / (256 - byte)` Hz), a codec byte and the samples. `ROL ` and `ADL `
  are an `MDhd` block (whose length counts only its data) followed by the MIDI file.

      {:ok, sound} = MonkeyXland.Scumm.Sound.parse(soun_body)
  """

  alias MonkeyXland.Scumm.Block

  @enforce_keys [:forms]
  defstruct @enforce_keys

  @type time :: {non_neg_integer(), non_neg_integer(), non_neg_integer()}
  @type form ::
          {:sample, pos_integer(), binary()}
          | {:roland, binary()}
          | {:adlib, binary()}
          | {:speaker, binary()}
          | {:cd,
             %{track: byte(), loops: pos_integer() | :forever, start: time(), finish: time()}}
  @type t :: %__MODULE__{forms: [form()]}

  @doc "Decodes a `SOUN` block body."
  @spec parse(binary()) :: {:ok, t()} | {:error, :bad_sound}
  def parse(<<"SOU ", _length::32, body::binary>>) do
    forms =
      for {tag, child} <- Block.children(body),
          form = block_form(tag, child),
          form != nil,
          do: form

    {:ok, %__MODULE__{forms: forms}}
  end

  def parse(
        <<_header::binary-16, track, loops, start_m, start_s, start_f, end_m, end_s, end_f,
          _rest::binary>>
      ) do
    cd = %{
      track: track,
      loops: loops(loops),
      start: {start_m, start_s, start_f},
      finish: {end_m, end_s, end_f}
    }

    {:ok, %__MODULE__{forms: [{:cd, cd}]}}
  end

  def parse(_body), do: {:error, :bad_sound}

  @doc "The form of `kind` (`:sample`, `:roland`, `:adlib`, `:speaker`, `:cd`), or `nil`."
  @spec form(t(), atom()) :: form() | nil
  def form(%__MODULE__{forms: forms}, kind), do: Enum.find(forms, &(elem(&1, 0) == kind))

  defp loops(0xFF), do: :forever
  defp loops(count), do: max(count, 1)

  defp block_form("SBL ", <<"AUhd", header::32, rest::binary>>) when byte_size(rest) >= header do
    <<_header::binary-size(^header), audio::binary>> = rest
    audio |> Block.children() |> List.keyfind("AUdt", 0) |> sample()
  end

  defp block_form("ROL ", body), do: midi_form(:roland, body)
  defp block_form("ADL ", body), do: midi_form(:adlib, body)
  defp block_form("SPK ", body), do: {:speaker, body}
  defp block_form(_tag, _body), do: nil

  defp midi_form(kind, <<"MDhd", length::32, rest::binary>>) when byte_size(rest) >= length do
    <<_header::binary-size(^length), midi::binary>> = rest
    {kind, midi}
  end

  defp midi_form(kind, body), do: {kind, body}

  defp sample({"AUdt", data}), do: voice(data, nil, [])
  defp sample(nil), do: nil

  defp voice(<<1, length::little-24, rate_byte, _codec, rest::binary>>, _rate, acc)
       when length >= 2 do
    count = min(length - 2, byte_size(rest))
    <<samples::binary-size(^count), rest::binary>> = rest
    voice(rest, div(1_000_000, 256 - rate_byte), [samples | acc])
  end

  defp voice(<<type, length::little-24, rest::binary>>, rate, acc)
       when type in 2..9 and byte_size(rest) >= length do
    <<_skipped::binary-size(^length), rest::binary>> = rest
    voice(rest, rate, acc)
  end

  defp voice(_rest, nil, _acc), do: nil

  defp voice(_rest, rate, acc),
    do: {:sample, rate, acc |> Enum.reverse() |> IO.iodata_to_binary()}
end
