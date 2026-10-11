defmodule MonkeyXland.GameTest do
  use ExUnit.Case, async: false

  @game System.get_env("MONKEYXLAND_GAME")
  @moduletag skip:
               if(@game, do: false, else: "set MONKEYXLAND_GAME to the Special Edition install")
  @moduletag timeout: :infinity

  setup_all do
    {:ok, assets} = MonkeyXland.Assets.load(@game)
    %{assets: assets}
  end

  test "every script, verb, entry and exit script in the game decodes", %{assets: assets} do
    programs =
      for {_number, room} <- assets.rooms,
          {code, entries} <-
            [{room.entry_script, [0]}, {room.exit_script, [0]}] ++
              Enum.map(room.local_scripts, fn {_n, code} -> {code, [0]} end) ++
              for(
                object <- room.objects,
                map_size(object.verbs) > 0,
                do: {object.script, Map.values(object.verbs)}
              ),
          code != <<>>,
          do: {code, entries}

    assert Enum.all?(programs, fn {code, entries} ->
             match?({:ok, _program}, GrogVM.Decode.program(code, entries))
           end)

    assert map_size(assets.globals) > 150
  end

  test "the game boots through the intro to the dock when the cutscenes are skipped" do
    state =
      Enum.reduce_while(1..80, MonkeyXland.Game.init(seed: 1), fn _round, state ->
        state = skip(state)
        if state.ctx.host.room == 33, do: {:halt, state}, else: {:cont, state}
      end)

    assert state.ctx.host.room == 33
    refute state.quit
  end

  test "the camera holds still once the player stops walking" do
    state =
      Enum.reduce_while(1..80, MonkeyXland.Game.init(seed: 1), fn _round, state ->
        if state.ctx.host.room == 33, do: {:halt, state}, else: {:cont, skip(state)}
      end)

    state = state |> ticks(60 * 12) |> click({250, 128}) |> ticks(60 * 8)

    cameras =
      state |> Stream.iterate(&ticks(&1, 6)) |> Enum.take(20) |> Enum.map(& &1.ctx.host.camera.x)

    assert MonkeyXland.World.actor(state.ctx.host, 1).walk == nil
    assert Enum.uniq(cameras) |> length() == 1
  end

  defp ticks(state, count),
    do: Enum.reduce(1..count, state, fn _tick, acc -> MonkeyXland.Game.step(acc, 1 / 60) end)

  defp click(state, {x, y}) do
    aim = {(x + 0.5) / 320, (y + 0.5) / 200}

    state
    |> MonkeyXland.Game.handle_input(:player, %{held: MapSet.new([:click]), aim: aim})
    |> ticks(2)
    |> MonkeyXland.Game.handle_input(:player, %{held: MapSet.new(), aim: aim})
  end

  defp skip(state) do
    aim = %{held: MapSet.new([:key_escape]), aim: {0.5, 0.5}}
    state = MonkeyXland.Game.handle_input(state, :player, aim)
    state = Enum.reduce(1..2, state, fn _tick, acc -> MonkeyXland.Game.step(acc, 1 / 60) end)
    state = MonkeyXland.Game.handle_input(state, :player, %{aim | held: MapSet.new()})
    Enum.reduce(1..120, state, fn _tick, acc -> MonkeyXland.Game.step(acc, 1 / 60) end)
  end
end
