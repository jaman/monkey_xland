defmodule MonkeyXland.Sounds do
  @moduledoc """
  Sounds and music the scripts start and stop, and how long each runs.

  Starting sound `n` chooses its form — CD music, a recording, Roland MIDI, AdLib MIDI,
  in that order — and adds an event for clients:

    * `{:play_cd, n, track}` (see `MonkeyXland.Scumm.Sound`),
    * `{:play_sample, n, rate, pcm}` — unsigned 8-bit mono PCM,
    * `{:play_midi, n, kind, midi}` — a Standard MIDI File, `kind` `:roland` or `:adlib`,
    * `{:stop_sound, n}` and `:stop_music`.

  A recording runs for its length, MIDI for its last event's time, and CD music for its
  track's length in the music bank, or until stopped when it loops forever. Sound `n`
  counts as running until then (`is_sound_running`).
  """

  alias MonkeyXland.{Assets, World}
  alias MonkeyXland.Scumm.Sound
  alias MonkeyXland.Xact.WaveBank

  @doc "Starts sound `number`; one with no form a client can play is ignored."
  @spec start(World.t(), non_neg_integer()) :: World.t()
  def start(world, number) do
    case Assets.sound(number) do
      nil -> world
      %Sound{} = sound -> sound |> playable() |> play(world, number)
    end
  end

  @doc "Stops sound `number`."
  @spec stop(World.t(), non_neg_integer()) :: World.t()
  def stop(world, number),
    do: %{World.emit(world, {:stop_sound, number}) | sounds: Map.delete(world.sounds, number)}

  @doc "Stops every piece of music."
  @spec stop_music(World.t()) :: World.t()
  def stop_music(world) do
    music = for {number, %{music: true}} <- world.sounds, do: number
    %{World.emit(world, :stop_music) | sounds: Map.drop(world.sounds, music)}
  end

  @doc "The audio track of the CD music playing, or `nil`."
  @spec cd_playing(World.t()) :: non_neg_integer() | nil
  def cd_playing(world),
    do: Enum.find_value(world.sounds, fn {_number, entry} -> Map.get(entry, :track) end)

  @doc "Whether sound `number` is still running."
  @spec running?(World.t(), non_neg_integer()) :: boolean()
  def running?(world, number), do: is_map_key(world.sounds, number)

  @doc "Counts `jiffies` off every running sound, forgetting those that have ended."
  @spec tick(World.t(), non_neg_integer()) :: World.t()
  def tick(world, jiffies) do
    sounds =
      for {number, entry} <- world.sounds,
          entry = count_down(entry, jiffies),
          entry != nil,
          into: %{},
          do: {number, entry}

    %{world | sounds: sounds}
  end

  defp playable(sound),
    do: Enum.find_value([:cd, :sample, :roland, :adlib], &Sound.form(sound, &1))

  defp play(nil, world, _number), do: world

  defp play({:cd, track}, world, number) do
    entry = %{music: true, loops: track.loops, left: cd_left(track), track: track.track}
    %{World.emit(world, {:play_cd, number, track}) | sounds: Map.put(world.sounds, number, entry)}
  end

  defp play({:sample, rate, pcm}, world, number) do
    entry = %{music: false, loops: 1, left: div(byte_size(pcm) * 60, rate) + 1}

    %{
      World.emit(world, {:play_sample, number, rate, pcm})
      | sounds: Map.put(world.sounds, number, entry)
    }
  end

  defp play({kind, midi}, world, number) when kind in [:roland, :adlib] do
    entry = %{music: true, loops: 1, left: midi_jiffies(midi)}

    %{
      World.emit(world, {:play_midi, number, kind, midi})
      | sounds: Map.put(world.sounds, number, entry)
    }
  end

  defp cd_left(%{loops: :forever}), do: :until_stopped

  defp cd_left(%{track: track}) do
    case Assets.cd_track(track) do
      nil -> :until_stopped
      entry -> round(WaveBank.seconds(entry) * 60) + 1
    end
  end

  defp midi_jiffies(midi) do
    case TuningFork.Midi.parse(midi) do
      {:ok, parsed} ->
        parsed
        |> TuningFork.Mt32.messages()
        |> Enum.map(&elem(&1, 0))
        |> Enum.max(fn -> 0.0 end)
        |> Kernel.*(60)
        |> round()
        |> Kernel.+(1)

      {:error, _reason} ->
        1
    end
  end

  defp count_down(%{left: :until_stopped} = entry, _jiffies), do: entry
  defp count_down(%{left: left}, jiffies) when left - jiffies <= 0, do: nil
  defp count_down(%{left: left} = entry, jiffies), do: %{entry | left: left - jiffies}
end
