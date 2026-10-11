defmodule MonkeyXland.Host.Actors do
  @moduledoc """
  Script operations on actors: placing, walking, turning, animating, their settings
  (`actor_ops`) and what scripts ask about them.
  """

  alias MonkeyXland.{Actor, Boxes, Camera, Context, Figure, Objects, Scene, Talk, Walking, World}

  @no_actor 0xFF

  @doc "Runs one actor operation."
  @spec op(GrogVM.Ctx.t(), tuple()) ::
          {:ok, GrogVM.Ctx.t()} | {:ok, integer() | boolean(), GrogVM.Ctx.t()}
  def op(ctx, {:put_actor, number, x, y}), do: {:ok, put(ctx, number, {x, y})}

  def op(ctx, {:put_actor_in_room, number, room}) do
    ctx = if talking_elsewhere?(ctx, number, room), do: Talk.stop(ctx), else: ctx

    ctx =
      Context.update(ctx, &World.update_actor(&1, number, fn actor -> %{actor | room: room} end))

    {:ok,
     if(room == 0,
       do:
         Context.update(
           ctx,
           &World.update_actor(&1, number, fn actor -> %{actor | x: 0, y: 0, visible: false} end)
         ),
       else: ctx
     )}
  end

  def op(ctx, {:put_actor_at_object, number, object}) do
    world = Context.world(ctx)
    point = Objects.position(world, object) || {240, 120}
    point = if World.actor?(world, object), do: {240, 120}, else: point
    {:ok, put(ctx, number, point)}
  end

  def op(ctx, {:walk_actor_to, number, x, y}),
    do: {:ok, Context.update(ctx, &Walking.start(&1, number, {x, y}, nil))}

  def op(ctx, {:walk_actor_to_actor, number, other, distance}) do
    world = Context.world(ctx)

    {:ok,
     Context.update(
       ctx,
       &walk_to_actor(&1, World.actor(world, number), World.actor(world, other), distance)
     )}
  end

  def op(ctx, {:walk_actor_to_object, number, object}) do
    case Objects.walk_point(Context.world(ctx), object) do
      nil -> {:ok, ctx}
      {point, facing} -> {:ok, Context.update(ctx, &Walking.start(&1, number, point, facing))}
    end
  end

  def op(ctx, {:face_actor, number, target}),
    do: {:ok, Context.update(ctx, &face(&1, number, target))}

  def op(ctx, {:animate_actor, number, animation}),
    do: {:ok, Context.update(ctx, &animate(&1, number, animation))}

  def op(ctx, {:actor_ops, number, ops}),
    do: {:ok, Enum.reduce(ops, ctx, &actor_op(&2, number, &1))}

  def op(ctx, {:actor_follow_camera, number}), do: {:ok, Camera.follow(ctx, number)}

  def op(ctx, {:get_actor_room, number}), do: value(ctx, number, & &1.room)
  def op(ctx, {:get_actor_elevation, number}), do: value(ctx, number, & &1.elevation)
  def op(ctx, {:get_actor_costume, number}), do: value(ctx, number, & &1.costume)
  def op(ctx, {:get_actor_width, number}), do: value(ctx, number, & &1.width)
  def op(ctx, {:get_actor_scale, number}), do: value(ctx, number, &elem(&1.scale, 0))
  def op(ctx, {:get_actor_walk_box, number}), do: value(ctx, number, & &1.box)
  def op(ctx, {:get_anim_counter, number}), do: value(ctx, number, & &1.anim_counter)
  def op(ctx, {:get_actor_facing, number}), do: value(ctx, number, &Actor.direction(&1.facing))
  def op(ctx, {:get_actor_moving, number}), do: value(ctx, number, &moving/1)

  def op(ctx, {:get_actor_x, number}), do: {:ok, coordinate(Context.world(ctx), number, 0), ctx}
  def op(ctx, {:get_actor_y, number}), do: {:ok, coordinate(Context.world(ctx), number, 1), ctx}

  def op(ctx, {:get_dist, first, second}),
    do: {:ok, Objects.distance(Context.world(ctx), first, second), ctx}

  def op(ctx, {:get_closest_obj_actor, number}) do
    world = Context.world(ctx)
    range = Context.var(ctx, :actor_range_min)..Context.var(ctx, :actor_range_max)//1

    closest =
      range
      |> Enum.reject(&(&1 == number))
      |> Enum.map(&{&1, Objects.distance(world, number, &1)})
      |> Enum.filter(fn {_other, distance} -> distance < 0xFF end)
      |> Enum.min_by(&elem(&1, 1), fn -> {@no_actor, 0xFF} end)
      |> elem(0)

    {:ok, closest, ctx}
  end

  def op(ctx, {:actor_from_pos, x, y}), do: {:ok, actor_at(Context.world(ctx), {x, y}), ctx}

  def op(ctx, {:is_actor_in_box, number, box}) do
    case World.actor(Context.world(ctx), number) do
      nil -> {:ok, false, ctx}
      actor -> {:ok, Boxes.inside?(Context.world(ctx), box, {actor.x, actor.y}), ctx}
    end
  end

  @doc "Puts actor `number` at `point` in its room, as SCUMM v5's `putActor` does."
  @spec put(GrogVM.Ctx.t(), non_neg_integer(), Boxes.point()) :: GrogVM.Ctx.t()
  def put(ctx, number, {x, y}) do
    ctx =
      if Context.var(ctx, :ego) == number,
        do: Context.update(ctx, &%{&1 | ego_positioned: true}),
        else: ctx

    Context.update(ctx, &placed(&1, number, {x, y}))
  end

  defp placed(world, number, {x, y}) do
    case World.actor(world, number) do
      nil ->
        world

      actor ->
        world
        |> World.update_actor(number, &%{&1 | x: x, y: y})
        |> placed_actor(%{actor | x: x, y: y})
    end
  end

  defp placed_actor(world, %Actor{visible: true, room: room} = actor)
       when room == world.room and room != 0 do
    world |> stand_still(actor) |> Walking.place(actor.number, {actor.x, actor.y})
  end

  defp placed_actor(world, %Actor{visible: true, number: number}),
    do: World.update_actor(world, number, &%{&1 | visible: false})

  defp placed_actor(world, %Actor{number: number, room: room})
       when room == world.room and room != 0, do: Scene.show(world, number)

  defp placed_actor(world, _actor), do: world

  defp stand_still(world, %Actor{walk: nil}), do: world

  defp stand_still(world, %Actor{number: number}),
    do: World.update_actor(world, number, &Actor.start_frame(%{&1 | walk: nil}, &1.frames.stand))

  defp talking_elsewhere?(ctx, number, room) do
    world = Context.world(ctx)
    actor = World.actor(world, number)

    actor != nil and actor.visible and world.room != room and
      Context.var(ctx, :talk_actor) == number
  end

  defp walk_to_actor(world, %Actor{room: room} = actor, %Actor{room: room} = other, distance)
       when room == world.room and room != 0 do
    distance = if distance == 0xFF, do: gap(actor, other), else: distance
    x = if other.x < actor.x, do: other.x + distance, else: other.x - distance
    Walking.start(world, actor.number, {x, other.y}, nil)
  end

  defp walk_to_actor(world, _actor, _other, _distance), do: world

  defp gap(%Actor{scale: {scale, _}, width: width}, %Actor{
         scale: {other_scale, _},
         width: other_width
       }),
       do: div(scale * width, 0xFF) + div(div(other_scale * other_width, 0xFF), 2)

  defp face(world, number, target) do
    with %Actor{room: room} = actor when room == world.room and room != 0 <-
           World.actor(world, number),
         {x, _y} <- Objects.position(world, target) do
      Walking.turn(world, number, if(x > actor.x, do: 90, else: 270))
    else
      _absent -> world
    end
  end

  defp animate(world, number, animation) do
    case World.actor(world, number) do
      %Actor{room: room, costume: costume} = actor
      when room == world.room and room != 0 and costume != 0 ->
        animated(world, number, Actor.animate(actor, animation))

      _absent ->
        world
    end
  end

  defp animated(world, number, {:stop_walking, actor}),
    do:
      World.update_actor(world, number, fn _old ->
        Actor.start_frame(%{actor | walk: nil}, actor.frames.stand)
      end)

  defp animated(world, number, {:turn, _actor, facing}), do: Walking.turn(world, number, facing)

  defp animated(world, number, %Actor{} = actor),
    do: World.update_actor(world, number, fn _old -> actor end)

  defp actor_op(ctx, number, {:costume, [costume]}),
    do: Context.update(ctx, &set_costume(&1, number, costume))

  defp actor_op(ctx, number, {:walk_speed, [x, y]}),
    do: change(ctx, number, &%{&1 | walk_speed: {x, y}})

  defp actor_op(ctx, number, {:sound, [sound]}), do: change(ctx, number, &%{&1 | sound: sound})

  defp actor_op(ctx, number, {:walk_animation, [frame]}),
    do: change(ctx, number, &put_frame(&1, walk: frame))

  defp actor_op(ctx, number, {:talk_animation, [start, stop]}),
    do: change(ctx, number, &put_frame(&1, talk_start: start, talk_stop: stop))

  defp actor_op(ctx, number, {:stand_animation, [frame]}),
    do: change(ctx, number, &put_frame(&1, stand: frame))

  defp actor_op(ctx, number, {:animations, [init, walk, stand]}),
    do: change(ctx, number, &put_frame(&1, init: init, walk: walk, stand: stand))

  defp actor_op(ctx, number, {:init, []}), do: change(ctx, number, &Actor.reset/1)

  defp actor_op(ctx, number, {:elevation, [elevation]}),
    do: change(ctx, number, &%{&1 | elevation: elevation})

  defp actor_op(ctx, number, {:default_animations, []}),
    do: change(ctx, number, &%{&1 | frames: Actor.new(0).frames})

  defp actor_op(ctx, number, {:palette, [index, color]}),
    do: change(ctx, number, &%{&1 | palette: Map.put(&1.palette, index, color)})

  defp actor_op(ctx, number, {:talk_color, [color]}),
    do: change(ctx, number, &%{&1 | talk_color: color})

  defp actor_op(ctx, number, {:name, [message]}),
    do:
      Context.update(
        ctx,
        &World.update_actor(&1, number, fn actor ->
          %{actor | name: MonkeyXland.Message.plain(&1, message)}
        end)
      )

  defp actor_op(ctx, number, {:init_animation, [frame]}),
    do: change(ctx, number, &put_frame(&1, init: frame))

  defp actor_op(ctx, number, {:width, [width]}), do: change(ctx, number, &%{&1 | width: width})
  defp actor_op(ctx, number, {:scale, [x, y]}), do: change(ctx, number, &%{&1 | scale: {x, y}})
  defp actor_op(ctx, number, {:never_z_clip, []}), do: change(ctx, number, &%{&1 | z_clip: :auto})

  defp actor_op(ctx, number, {:always_z_clip, [plane]}),
    do: change(ctx, number, &%{&1 | z_clip: z_clip(plane)})

  defp actor_op(ctx, number, {:ignore_boxes, []}),
    do: ctx |> change(number, &%{&1 | ignore_boxes: true, z_clip: :auto}) |> replace(number)

  defp actor_op(ctx, number, {:follow_boxes, []}),
    do: ctx |> change(number, &%{&1 | ignore_boxes: false, z_clip: :auto}) |> replace(number)

  defp actor_op(ctx, number, {:animation_speed, [speed]}),
    do: change(ctx, number, &%{&1 | anim_speed: speed, anim_progress: 0})

  defp actor_op(ctx, number, {:shadow, [mode]}), do: change(ctx, number, &%{&1 | shadow: mode})
  defp actor_op(ctx, _number, {:dummy, [_value]}), do: ctx

  defp z_clip(0), do: :auto
  defp z_clip(plane), do: plane

  defp change(ctx, number, fun), do: Context.update(ctx, &World.update_actor(&1, number, fun))

  defp put_frame(actor, frames), do: %{actor | frames: Map.merge(actor.frames, Map.new(frames))}

  defp replace(ctx, number) do
    world = Context.world(ctx)

    case World.actor(world, number) do
      %Actor{room: room, x: x, y: y} when room == world.room and room != 0 ->
        put(ctx, number, {x, y})

      _elsewhere ->
        ctx
    end
  end

  defp set_costume(world, number, costume) do
    World.update_actor(world, number, fn actor ->
      %{
        actor
        | costume: costume,
          limbs: %{},
          stopped: MapSet.new(),
          palette: %{},
          needs_init: true
      }
    end)
    |> reinit_visible(number)
  end

  defp reinit_visible(world, number) do
    case World.actor(world, number) do
      %Actor{visible: true} ->
        world |> World.update_actor(number, &%{&1 | visible: false}) |> Scene.show(number)

      _hidden ->
        world
    end
  end

  defp value(ctx, number, read) do
    case World.actor(Context.world(ctx), number) do
      nil -> {:ok, 0, ctx}
      actor -> {:ok, read.(actor), ctx}
    end
  end

  defp moving(%Actor{walk: nil}), do: 0
  defp moving(%Actor{walk: %{turn: _facing}}), do: 4
  defp moving(%Actor{walk: %{leg: nil}}), do: 1
  defp moving(%Actor{walk: %{last: true}}), do: 10
  defp moving(%Actor{}), do: 2

  defp coordinate(world, number, axis) do
    case Objects.position(world, number) do
      nil -> -1
      point -> elem(point, axis)
    end
  end

  defp actor_at(world, {x, y}) do
    world
    |> World.actors_in_room()
    |> Enum.filter(&(&1.visible and not Objects.class?(world, &1.number, 32)))
    |> Enum.find_value(0, fn actor ->
      case Figure.bounds(actor) do
        {left, top, right, bottom} when x >= left and x < right and y >= top and y <= bottom ->
          actor.number

        _other ->
          nil
      end
    end)
  end
end
