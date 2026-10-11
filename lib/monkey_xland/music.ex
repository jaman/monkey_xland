defmodule MonkeyXland.Music do
  @moduledoc """
  The game's CD music for `Cauldron2D.Audio.Music`: one piece, `"monkey-cd"`, with a
  section for each audio track and one of silence, each section rendered only when cued
  (`render: :on_cue`).

  A track's audio is its entry in the music bank: 16-bit stereo PCM as it is, or xWMA
  decoded by `TuningFork.Xwma`; on a machine without an xWMA decoder those sections are
  silence.
  """

  alias MonkeyXland.Assets
  alias MonkeyXland.Xact.WaveBank
  alias TuningFork.Xwma

  @piece "monkey-cd"
  @rate 44_100
  @tracks 1..24

  @doc "The piece's name."
  @spec piece() :: String.t()
  def piece, do: @piece

  @doc "The piece, ready for `Cauldron2D.Client.Game.music/0`."
  @spec spec() :: Cauldron2D.Audio.Music.spec()
  def spec do
    sections = Map.new(@tracks, fn track -> {section(track), %{cd: fn -> pcm(track) end}} end)

    %{
      bpm: 600,
      beats_per_bar: 1,
      layers: [:cd],
      render: :on_cue,
      sections: Map.put(sections, :silence, %{cd: {:pcm, silence()}}),
      fingerprint: "monkey-cd-1"
    }
  end

  @doc "The section for audio track `track`, or `:silence` for `nil`."
  @spec section(non_neg_integer() | nil) :: atom()
  def section(nil), do: :silence
  def section(track), do: :"track_#{track}"

  @doc "Audio track `track` as 44.1 kHz stereo signed 16-bit PCM, silence when it cannot be decoded."
  @spec pcm(non_neg_integer()) :: binary()
  def pcm(track) do
    bank = Assets.get().music

    with entry when entry != nil <- Assets.cd_track(track),
         {:ok, bytes} <- WaveBank.read(bank, entry),
         {:ok, pcm} <- decoded(entry, bytes) do
      pcm
    else
      _cannot -> silence()
    end
  end

  defp decoded(%{codec: :pcm, bits: 16, channels: 2, rate: @rate}, bytes), do: {:ok, bytes}

  defp decoded(%{codec: :wma} = entry, packets) do
    case packets |> Xwma.riff(entry) |> Xwma.decode() do
      {:ok, pcm, %{rate: @rate, channels: 2}} -> {:ok, pcm}
      _other -> :error
    end
  end

  defp decoded(_entry, _bytes), do: :error

  defp silence, do: :binary.copy(<<0, 0, 0, 0>>, div(@rate, 10))
end
