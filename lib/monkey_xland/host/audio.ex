defmodule MonkeyXland.Host.Audio do
  @moduledoc """
  Script operations on sound and music, and on the game itself (restart, pause, quit).
  """

  alias MonkeyXland.{Context, Sounds, World}

  @system %{1 => :restart, 2 => :pause, 3 => :quit}

  @doc "Runs one sound or system operation."
  @spec op(GrogVM.Ctx.t(), tuple()) :: {:ok, GrogVM.Ctx.t()} | {:ok, integer(), GrogVM.Ctx.t()}
  def op(ctx, {name, number}) when name in [:start_sound, :start_music] do
    {:ok, ctx |> Context.update(&Sounds.start(&1, number)) |> Context.put_var(:music_timer, 0)}
  end

  def op(ctx, {:stop_sound, number}), do: {:ok, Context.update(ctx, &Sounds.stop(&1, number))}
  def op(ctx, {:stop_music}), do: {:ok, Context.update(ctx, &Sounds.stop_music/1)}

  def op(ctx, {:is_sound_running, number}),
    do: {:ok, if(Sounds.running?(Context.world(ctx), number), do: 1, else: 0), ctx}

  def op(ctx, {:sound_kludge, _commands}), do: {:ok, ctx}

  def op(ctx, {:system_ops, code}),
    do: {:ok, Context.update(ctx, &World.emit(&1, {:system, Map.get(@system, code, code)}))}
end
