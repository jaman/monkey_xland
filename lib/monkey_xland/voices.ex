defmodule MonkeyXland.Voices do
  @moduledoc """
  The Special Edition voice clip for each page of a message a script prints, found
  through `MonkeyXland.SpeechInfo` by where the `print` is: the room, the local script
  or object (0 for room and global scripts), the offset of the instruction — for an
  object, from the start of the verb's code — and the page.

  A voice is `%{index: n, seconds: s}`: entry `n` of the speech bank, `s` seconds long.
  """

  alias MonkeyXland.{Assets, Context, Message, SpeechInfo}
  alias MonkeyXland.Scumm.Index
  alias MonkeyXland.Xact.WaveBank

  @type voice :: %{index: non_neg_integer(), seconds: float()}

  @doc "One voice (or `nil`) for each page of `parts` printed by the instruction running in `ctx`."
  @spec for_message(GrogVM.Ctx.t(), [term()]) :: [voice() | nil]
  def for_message(ctx, parts) do
    case place(ctx) do
      nil ->
        []

      {room, number, offset} ->
        ctx
        |> Context.world()
        |> Message.pages(parts, 0)
        |> Enum.with_index()
        |> Enum.map(&page_voice(&1, room, number, offset))
    end
  end

  defp page_voice({lines, page}, room, number, offset),
    do: voice({room, number, offset, page}, text(lines))

  defp place(%GrogVM.Ctx{at: nil}), do: nil

  defp place(%GrogVM.Ctx{at: at} = ctx) do
    world = Context.world(ctx)

    case GrogVM.current(ctx) do
      %{kind: :local, number: number} ->
        {world.room_resource, number, at}

      %{kind: :room} ->
        {world.room_resource, 0, at}

      %{kind: kind, number: object, entry: entry} when kind in [:object, :inventory] ->
        {Map.get(Assets.get().object_rooms, object, 0), object, at - entry}

      %{kind: :global, number: number} ->
        {global_room(number), 0, at}

      nil ->
        nil
    end
  end

  defp global_room(number) do
    case Index.locate(Assets.get().install.index, :script, number) do
      {:ok, {room, _offset}} -> room
      _missing -> 0
    end
  end

  defp text(lines),
    do: Enum.map_join(lines, " ", fn runs -> Enum.map_join(runs, &elem(&1, 0)) end)

  defp voice(key, text) do
    assets = Assets.get()

    with cue when cue != nil <- SpeechInfo.find(assets.speech_info, key, text),
         index when index != nil <- Map.get(assets.speech_cues, cue) do
      %{index: index, seconds: assets.speech.entries |> Enum.at(index) |> WaveBank.seconds()}
    else
      _none -> nil
    end
  end
end
