defmodule MonkeyXland.Camera do
  @moduledoc """
  The camera: the room x at the centre of the screen.

  Each frame, from a multiple of 8, it moves 8 pixels right when short of where it is
  going and then 8 left when past it, so it comes to rest on the multiple of 8 at or
  below its destination — or it jumps there when variable 26 (`camera_fast_x`) is set —
  staying between variables 17 and 18. Following an actor, it
  sets off when the actor stands left of strip 10 or right of strip 30 of the screen,
  and stops once it is over the actor's strip. When it has moved, the script variable 27
  names (`scroll_script`) runs.
  """

  import Bitwise

  alias MonkeyXland.{Context, Scene, World}

  @left_trigger 10
  @right_trigger 30

  @doc "The room x of the screen's left edge."
  @spec left(World.t()) :: integer()
  def left(%World{camera: %{x: x}, room_data: %{width: width}}),
    do: (x - div(World.screen_width(), 2)) |> min(width - World.screen_width()) |> max(0)

  def left(%World{}), do: 0

  @doc "Moves the camera one frame on."
  @spec move(GrogVM.Ctx.t()) :: GrogVM.Ctx.t()
  def move(ctx) do
    world = Context.world(ctx)
    before = world.camera.x
    camera = %{world.camera | x: before &&& bnot(7)}

    {low, high, fast} =
      {Context.var(ctx, :camera_min_x), Context.var(ctx, :camera_max_x),
       Context.var(ctx, :camera_fast_x) != 0}

    camera = step(camera, world, low, high, fast)
    ctx |> Context.update(&%{&1 | camera: camera}) |> scrolled(before)
  end

  @doc "Puts the camera at room x `x`, out of any follow."
  @spec set_at(GrogVM.Ctx.t(), integer()) :: GrogVM.Ctx.t()
  def set_at(ctx, x) do
    ctx
    |> Context.update(&%{&1 | camera: %{&1.camera | mode: :normal, moving_to_actor: false}})
    |> place(x)
  end

  @doc "Sends the camera toward room x `x`, 8 pixels a frame."
  @spec pan_to(GrogVM.Ctx.t(), integer()) :: GrogVM.Ctx.t()
  def pan_to(ctx, x),
    do:
      Context.update(
        ctx,
        &%{&1 | camera: %{&1.camera | dest: x, mode: :panning, moving_to_actor: false}}
      )

  @doc "Makes the camera follow actor `number`, changing to its room when it is elsewhere."
  @spec follow(GrogVM.Ctx.t(), non_neg_integer()) :: GrogVM.Ctx.t()
  def follow(ctx, number) do
    ctx = Context.update(ctx, &%{&1 | camera: %{&1.camera | mode: :follow, follows: number}})
    world = Context.world(ctx)

    case World.actor(world, number) do
      nil -> ctx
      actor -> follow_actor(ctx, world, actor)
    end
  end

  defp follow_actor(ctx, world, actor) when actor.room != world.room do
    ctx
    |> Scene.start(actor.room)
    |> Context.update(
      &%{&1 | camera: %{&1.camera | mode: :follow, follows: actor.number, x: actor.x}}
    )
    |> place(actor.x)
    |> follow_actor_in_room(actor.number)
  end

  defp follow_actor(ctx, _world, actor), do: follow_actor_in_room(ctx, actor.number)

  defp follow_actor_in_room(ctx, number) do
    world = Context.world(ctx)
    actor = World.actor(world, number)
    strip = div(actor.x, 8) - screen_start_strip(world.camera.x)
    ctx = if strip < @left_trigger or strip > @right_trigger, do: place(ctx, actor.x), else: ctx
    run_inventory_script(ctx)
  end

  defp run_inventory_script(ctx) do
    case Context.var(ctx, :inventory_script) do
      0 -> ctx
      script -> GrogVM.start_script(ctx, script, [0])
    end
  end

  defp place(ctx, x) do
    world = Context.world(ctx)
    camera = world.camera

    current =
      if camera.mode != :follow or abs(x - camera.x) > div(World.screen_width(), 2),
        do: x,
        else: camera.x

    current =
      current |> max(Context.var(ctx, :camera_min_x)) |> min(Context.var(ctx, :camera_max_x))

    ctx |> Context.update(&%{&1 | camera: %{camera | x: current, dest: x}}) |> run_scroll_script()
  end

  defp step(camera, _world, low, _high, fast) when camera.x < low,
    do: %{camera | x: if(fast, do: low, else: camera.x + 8)}

  defp step(camera, _world, _low, high, fast) when camera.x > high,
    do: %{camera | x: if(fast, do: high, else: camera.x - 8)}

  defp step(camera, world, low, high, fast) do
    camera = follow_trigger(camera, world, fast)
    actor_x = if camera.moving_to_actor, do: following_x(world, camera), else: nil
    dest = (actor_x || camera.dest) |> max(low) |> min(high)
    x = if fast, do: dest, else: camera.x |> toward_right(dest) |> back_left(dest)

    arrived = camera.moving_to_actor and actor_x != nil and div(x, 8) == div(actor_x, 8)
    %{camera | x: x, dest: dest, moving_to_actor: camera.moving_to_actor and not arrived}
  end

  defp toward_right(x, dest) when x < dest, do: x + 8
  defp toward_right(x, _dest), do: x

  defp back_left(x, dest) when x > dest, do: x - 8
  defp back_left(x, _dest), do: x

  defp follow_trigger(%{mode: :follow} = camera, world, fast) do
    case following_x(world, camera) do
      nil -> camera
      actor_x -> trigger(camera, actor_x, div(actor_x, 8) - screen_start_strip(camera.x), fast)
    end
  end

  defp follow_trigger(camera, _world, _fast), do: camera

  defp trigger(camera, _actor_x, strip, _fast)
       when strip >= @left_trigger and strip <= @right_trigger, do: camera

  defp trigger(camera, actor_x, strip, true) when strip > 35, do: %{camera | dest: actor_x + 80}
  defp trigger(camera, actor_x, strip, true) when strip < 5, do: %{camera | dest: actor_x - 80}
  defp trigger(camera, _actor_x, _strip, true), do: camera
  defp trigger(camera, _actor_x, _strip, false), do: %{camera | moving_to_actor: true}

  defp following_x(world, %{follows: number}) do
    case World.actor(world, number) do
      nil -> nil
      actor -> actor.x
    end
  end

  defp screen_start_strip(camera_x), do: div(camera_x, 8) - 20

  defp scrolled(ctx, before) do
    if Context.world(ctx).camera.x != before, do: run_scroll_script(ctx), else: ctx
  end

  defp run_scroll_script(ctx) do
    ctx = Context.put_var(ctx, :camera_pos_x, Context.world(ctx).camera.x)

    case Context.var(ctx, :scroll_script) do
      0 -> ctx
      script -> GrogVM.start_script(ctx, script, [])
    end
  end
end
