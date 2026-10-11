defmodule MonkeyXland.Audio do
  @moduledoc """
  The voices the game's sounds make, for `Cauldron2D.Audio`.

    * `{:sample, n}` — sound `n`'s recording, 8-bit PCM at its own rate,
    * `{:midi, n}` — sound `n`'s Roland (or AdLib) music: through the player's own
      Munt when `MUNT_LOCATION` is set (`TuningFork.Mt32`), otherwise through
      `TuningFork.Gm`,
    * `{:speech, index}` — entry `index` of the speech bank, 16-bit PCM.

  Each is decoded the first time it is asked for and kept.

  `events/1` turns the world's sound events (`MonkeyXland.Sounds`) into
  `Cauldron2D.Audio` events: every sound plays under its own key, so starting it again
  replaces it and stopping it stops it; music plays under `:music`, the voice under
  `:voice`. CD music is `MonkeyXland.Music`, cued from the view.
  """

  alias Cauldron2D.Audio, as: CauldronAudio
  alias MonkeyXland.Assets
  alias MonkeyXland.Scumm.Sound
  alias MonkeyXland.Xact.WaveBank
  alias TuningFork.{Gm, Midi, Mt32, Sample, Score, Voice}

  @rate 44_100

  @doc "The Cauldron audio events for the world's sound events."
  @spec events([term()]) :: [term()]
  def events(world_events), do: Enum.flat_map(world_events, &event/1)

  @doc "The voice for a sound name, or `nil` when it has none."
  @spec voice(term()) :: Voice.t() | nil
  def voice(name) do
    key = {__MODULE__, name}

    case :persistent_term.get(key, :unread) do
      :unread -> tap(build(name), &:persistent_term.put(key, &1))
      voice -> voice
    end
  end

  defp event({:play_sample, number, _rate, _pcm}),
    do: [CauldronAudio.keyed({:sound, number}, {:sample, number})]

  defp event({:play_midi, number, _kind, _midi}),
    do: [CauldronAudio.keyed(:music, {:midi, number})]

  defp event({:play_voice, index}), do: [CauldronAudio.keyed(:voice, {:speech, index})]
  defp event({:stop_sound, number}), do: [CauldronAudio.stopped({:sound, number})]
  defp event(:stop_voice), do: [CauldronAudio.stopped(:voice)]
  defp event(:stop_music), do: [CauldronAudio.stopped(:music)]
  defp event(_other), do: []

  defp build({:sample, number}) do
    case Assets.sound(number) && Sound.form(Assets.sound(number), :sample) do
      {:sample, rate, pcm} ->
        pcm
        |> signed_16()
        |> Sample.from_pcm(rate: rate, root: 440.0, name: "sound #{number}")
        |> as_voice()

      _none ->
        nil
    end
  end

  defp build({:midi, number}) do
    with %Sound{} = sound <- Assets.sound(number),
         {_kind, bytes} <- Sound.form(sound, :roland) || Sound.form(sound, :adlib),
         {:ok, midi} <- Midi.parse(bytes) do
      midi |> render_midi() |> as_voice()
    else
      _none -> nil
    end
  end

  defp build({:speech, index}) do
    bank = Assets.get().speech

    with %{codec: :pcm, bits: 16} = entry <- Enum.at(bank.entries, index),
         {:ok, pcm} <- WaveBank.read(bank, entry) do
      pcm
      |> Sample.from_pcm(
        rate: entry.rate,
        channels: entry.channels,
        root: 440.0,
        name: "speech #{index}"
      )
      |> as_voice()
    else
      _none -> nil
    end
  end

  defp render_midi(midi) do
    with true <- Mt32.available?(),
         {:ok, synth} <- Mt32.open(),
         {:ok, sample} <- Mt32.render_midi(synth, midi) do
      Mt32.close(synth)
      sample
    else
      _no_munt ->
        midi
        |> Gm.score()
        |> Score.render(@rate)
        |> Sample.from_pcm(rate: @rate, channels: 2, root: 440.0, name: "music")
    end
  end

  defp as_voice(%Sample{} = sample), do: Voice.new(sample: sample, freq: 440.0, gain: 0.8)

  defp signed_16(unsigned),
    do: for(<<byte <- unsigned>>, into: <<>>, do: <<(byte - 128) * 256::16-signed-little>>)
end
