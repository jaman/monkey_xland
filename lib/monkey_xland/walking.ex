defmodule MonkeyXland.Walking do
  @moduledoc """
  Actors walking and turning, one frame at a time.

  A walk crosses boxes in legs: from the box an actor stands in to the next box on the
  route, aiming for the point of the opening between them nearest the destination, until
  the destination's box is reached and the last leg goes straight to the destination.
  Each step moves the actor by its walk speed, scaled by the box it is in: the faster of
  its two speeds limits the axis that moves most. An actor turns a quarter at a time,
  one quarter a frame.

  An actor's `walk` is `nil` when it stands, or `%{dest: point, dest_box: box,
  dest_facing: degrees | nil, target_box: box, last: boolean, leg: leg | nil}`; while
  turning in place it is `%{turn: degrees}`.
  """

  import Bitwise

  alias MonkeyXland.{Actor, Boxes, World}

  @doc """
  Starts actor `number` walking to `point`, facing `facing` (degrees, or `nil`) when it
  arrives. An actor outside the current room is put there at once.
  """
  @spec start(World.t(), non_neg_integer(), Boxes.point(), integer() | nil) :: World.t()
  def start(world, number, point, facing) do
    case World.actor(world, number) do
      nil -> world
      actor -> start_actor(world, actor, point, facing)
    end
  end

  @doc "Turns actor `number` toward `facing`, a quarter a frame."
  @spec turn(World.t(), non_neg_integer(), integer()) :: World.t()
  def turn(world, number, facing) do
    World.update_actor(world, number, fn
      %Actor{facing: ^facing} = actor -> actor
      actor -> %{actor | walk: %{turn: Integer.mod(facing, 360)}}
    end)
  end

  @doc "Stops actor `number` where it stands."
  @spec stop(World.t(), non_neg_integer()) :: World.t()
  def stop(world, number), do: World.update_actor(world, number, &%{&1 | walk: nil})

  @doc "Whether actor `number` is walking or turning."
  @spec moving?(World.t(), non_neg_integer()) :: boolean()
  def moving?(world, number),
    do: match?(%Actor{walk: walk} when walk != nil, World.actor(world, number))

  @doc "Moves every walking or turning actor in the current room one frame on."
  @spec step_all(World.t()) :: World.t()
  def step_all(world) do
    world
    |> World.actors_in_room()
    |> Enum.filter(& &1.walk)
    |> Enum.reduce(world, &step(&2, &1.number))
  end

  @doc "Places actor `number` at `point` in the box that holds it, nearest box first; stops any walk."
  @spec place(World.t(), non_neg_integer(), Boxes.point()) :: World.t()
  def place(world, number, point) do
    case World.actor(world, number) do
      %Actor{ignore_boxes: true} ->
        World.update_actor(world, number, &%{put_point(&1, point) | walk: nil, box: 0})

      %Actor{} ->
        place_in_box(world, number, Boxes.adjust(world, point))

      nil ->
        world
    end
  end

  defp place_in_box(world, number, {point, box}) do
    world
    |> World.update_actor(number, &%{put_point(&1, point) | walk: nil})
    |> enter_box(number, box)
  end

  defp put_point(actor, {x, y}), do: %{actor | x: x, y: y}

  defp start_actor(world, %Actor{room: room} = actor, point, _facing)
       when room != world.room or room == 0 do
    {point, box} = destination(world, actor, point)
    World.update_actor(world, actor.number, &%{put_point(&1, point) | box: box})
  end

  defp start_actor(world, %Actor{} = actor, point, facing) do
    {dest, dest_box} = destination(world, actor, point)

    case {actor.x, actor.y} == dest do
      true ->
        if facing && facing != actor.facing, do: turn(world, actor.number, facing), else: world

      false ->
        World.update_actor(
          world,
          actor.number,
          &%{
            &1
            | walk: %{
                dest: dest,
                dest_box: dest_box,
                dest_facing: facing,
                target_box: &1.box,
                last: false,
                leg: nil
              }
          }
        )
    end
  end

  defp destination(_world, %Actor{ignore_boxes: true}, point), do: {point, 0}
  defp destination(world, _actor, point), do: Boxes.adjust(world, point)

  defp step(world, number) do
    actor = World.actor(world, number)
    step_walk(world, actor, actor.walk)
  end

  defp step_walk(world, actor, %{turn: target}) do
    case turned(actor.facing, target) do
      ^target -> World.update_actor(world, actor.number, &%{Actor.face(&1, target) | walk: nil})
      facing -> World.update_actor(world, actor.number, &Actor.face(&1, facing))
    end
  end

  defp step_walk(world, actor, %{leg: nil} = walk), do: plan(world, actor, walk)

  defp step_walk(world, actor, %{leg: leg} = walk) do
    case walk_step(actor, leg) do
      {:moving, actor} ->
        World.update_actor(world, actor.number, fn _old -> enter_target(world, actor) end)

      {:arrived, actor} ->
        leg_done(world, actor, walk)
    end
  end

  defp leg_done(world, actor, %{last: true} = walk) do
    world
    |> World.update_actor(actor.number, fn _old -> %{actor | walk: nil} end)
    |> enter_box(actor.number, walk.dest_box)
    |> World.update_actor(actor.number, &Actor.start_frame(&1, &1.frames.stand))
    |> finish_facing(actor.number, walk.dest_facing)
  end

  defp leg_done(world, actor, walk) do
    world
    |> World.update_actor(actor.number, fn _old -> %{actor | walk: %{walk | leg: nil}} end)
    |> enter_box(actor.number, walk.target_box)
    |> then(&plan(&1, World.actor(&1, actor.number), World.actor(&1, actor.number).walk))
  end

  defp finish_facing(world, _number, nil), do: world
  defp finish_facing(world, number, facing), do: turn(world, number, facing)

  defp plan(world, %Actor{box: box} = actor, %{dest_box: dest_box} = walk)
       when box == dest_box or box == 0 or actor.ignore_boxes,
       do: begin_leg(world, actor, %{walk | last: true, target_box: dest_box}, walk.dest)

  defp plan(world, %Actor{box: box} = actor, %{dest_box: dest_box} = walk) do
    case Boxes.next_box(world, box, dest_box) do
      nil -> stand_here(world, actor, walk)
      next -> plan_through(world, actor, walk, next)
    end
  end

  defp plan_through(world, actor, walk, next) do
    boxes = Boxes.all(world)

    case locked?(world, next) do
      true ->
        stand_here(world, actor, walk)

      false ->
        aim(
          world,
          actor,
          %{walk | target_box: next},
          boxes |> gate_between(actor.box, next) |> Boxes.nearest_on_segment(walk.dest)
        )
    end
  end

  defp aim(world, actor, walk, point) when point == {actor.x, actor.y} do
    world = enter_box(world, actor.number, walk.target_box)
    plan(world, World.actor(world, actor.number), walk)
  end

  defp aim(world, actor, walk, point), do: begin_leg(world, actor, walk, point)

  defp stand_here(world, actor, walk) do
    World.update_actor(
      world,
      actor.number,
      &%{&1 | walk: %{walk | dest: {actor.x, actor.y}, dest_box: actor.box, last: true, leg: nil}}
    )
    |> then(fn world ->
      leg_done(world, World.actor(world, actor.number), World.actor(world, actor.number).walk)
    end)
  end

  defp locked?(world, box), do: (Boxes.flags(world, box) &&& 0x40) != 0

  defp gate_between(boxes, from, to),
    do: Boxes.gate(Map.fetch!(boxes, from), Map.fetch!(boxes, to))

  defp begin_leg(world, actor, walk, {x, y} = target) when {x, y} == {actor.x, actor.y},
    do: leg_done(world, actor, %{walk | leg: nil, dest: target})

  defp begin_leg(world, actor, walk, target) do
    leg = movement(actor, target)
    actor = %{actor | walk: %{walk | leg: leg}}
    actor = start_walk_animation(actor, angle(leg.dx, leg.dy))

    case walk_step(actor, leg) do
      {:moving, actor} ->
        World.update_actor(world, actor.number, fn _old -> enter_target(world, actor) end)

      {:arrived, actor} ->
        leg_done(world, actor, actor.walk)
    end
  end

  defp start_walk_animation(%Actor{} = actor, facing) do
    if actor.frame != actor.frames.walk or actor.facing != facing,
      do: actor |> Actor.face(facing) |> Actor.start_frame(actor.frames.walk),
      else: actor
  end

  defp movement(%Actor{walk_speed: {speed_x, speed_y}, x: x, y: y}, {to_x, to_y}) do
    {dx, dy} = {to_x - x, to_y - y}
    y_factor = if dy < 0, do: -(speed_y <<< 16), else: speed_y <<< 16

    {x_factor, y_factor} =
      if dy != 0, do: {div(y_factor * dx, dy), y_factor}, else: {y_factor * dx, 0}

    {x_factor, y_factor} =
      if abs(x_factor) > speed_x <<< 16 do
        x_factor = if dx < 0, do: -(speed_x <<< 16), else: speed_x <<< 16
        if dx != 0, do: {x_factor, div(x_factor * dy, dx)}, else: {0, x_factor * dy}
      else
        {x_factor, y_factor}
      end

    %{from: {x, y}, to: {to_x, to_y}, dx: x_factor, dy: y_factor, fraction: {0, 0}}
  end

  defp walk_step(
         %Actor{x: x, y: y, scale: {scale_x, scale_y}} = actor,
         %{from: {from_x, from_y}, to: {to_x, to_y}} = leg
       ) do
    {distance_x, distance_y} = {abs(to_x - from_x), abs(to_y - from_y)}

    if abs(x - from_x) >= distance_x and abs(y - from_y) >= distance_y do
      {:arrived, actor}
    else
      {fraction_x, fraction_y} = leg.fraction
      moved_x = (x <<< 16) + fraction_x + (leg.dx >>> 8) * scale_x
      moved_y = (y <<< 16) + fraction_y + (leg.dy >>> 8) * scale_y
      new_x = if abs((moved_x >>> 16) - from_x) > distance_x, do: to_x, else: moved_x >>> 16
      new_y = if abs((moved_y >>> 16) - from_y) > distance_y, do: to_y, else: moved_y >>> 16
      leg = %{leg | fraction: {moved_x &&& 0xFFFF, moved_y &&& 0xFFFF}}
      {:moving, %{actor | x: new_x, y: new_y, walk: %{actor.walk | leg: leg}}}
    end
  end

  defp enter_target(world, %Actor{walk: %{target_box: target}} = actor)
       when target != actor.box do
    if Boxes.inside?(world, target, {actor.x, actor.y}),
      do: with_box(world, actor, target),
      else: actor
  end

  defp enter_target(_world, actor), do: actor

  defp enter_box(world, number, box),
    do: World.update_actor(world, number, &with_box(world, &1, box))

  defp with_box(_world, %Actor{ignore_boxes: true} = actor, box), do: %{actor | box: box}

  defp with_box(world, actor, box) do
    scale = Boxes.scale(world, box, actor.y)
    %{actor | box: box, scale: {scale, scale}}
  end

  defp angle(dx, dy) when abs(dy) * 2 < abs(dx), do: if(dx > 0, do: 90, else: 270)
  defp angle(_dx, dy), do: if(dy > 0, do: 180, else: 0)

  defp turned(from, to) do
    from_quarter = quarter(from)
    to_quarter = quarter(to)
    diff = to_quarter - from_quarter
    diff = if abs(diff) > 2, do: -diff, else: diff
    step = if diff > 0, do: 1, else: if(diff < 0, do: -1, else: 0)
    if step == 0, do: to, else: Integer.mod(from_quarter + step, 4) * 90
  end

  defp quarter(facing) when facing in 71..109, do: 1
  defp quarter(facing) when facing in 109..251, do: 2
  defp quarter(facing) when facing in 251..289, do: 3
  defp quarter(_facing), do: 0
end
