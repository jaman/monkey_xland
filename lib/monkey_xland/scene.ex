defmodule MonkeyXland.Scene do
  @moduledoc """
  Changing rooms, in the order SCUMM v5 does it:

    1. the exit scripts run: the global one variable 30 names, the room's own, the one
       variable 31 names;
    2. the room's scripts end — entry, exit, local and object scripts, but not global
       scripts or those of carried objects;
    3. the new room is loaded: its objects, boxes, palette and cycles; the camera limits
       (variables 17 and 18) become half a screen in from each edge and the camera
       centres on the left; `room` (4) and `room_resource` (22) are set;
    4. an actor arriving by an object is put at the object's walk point, facing away from
       it;
    5. the entry scripts run: variable 28's, the room's own, variable 29's.

  Room numbers from `0x80` up are mapped to rooms through `pseudo_room`.
  """

  alias MonkeyXland.{Actor, Assets, Context, Objects, Palette, Talk, Walking, World}

  @doc "Changes to `room`; `actor` arrives by `object` when both are given."
  @spec start(GrogVM.Ctx.t(), non_neg_integer(), non_neg_integer() | nil, non_neg_integer() | nil) ::
          GrogVM.Ctx.t()
  def start(ctx, room, actor \\ nil, object \\ nil) do
    ctx
    |> Talk.stop()
    |> Context.put_var(:new_room, room)
    |> run_scripts(:exit_script, :exit, :exit_script_2)
    |> GrogVM.stop_where(&(&1.kind in [:room, :local, :object]))
    |> Context.update(&hide_actors/1)
    |> Context.update(&load(&1, room))
    |> set_room_vars(room)
    |> arrive(actor, object)
    |> Context.update(&show_actors/1)
    |> Context.update(&%{&1 | ego_positioned: false})
    |> run_scripts(:entry_script, :entry, :entry_script_2)
    |> settle_arrival(actor, object)
    |> Context.update(&put_in(&1.effect.pending, true))
  end

  @doc "The room resource a room number names."
  @spec resource(World.t(), non_neg_integer()) :: non_neg_integer()
  def resource(world, room) when room >= 0x80, do: Map.get(world.pseudo_rooms, room - 0x80, room)
  def resource(_world, room), do: room

  defp hide_actors(world),
    do: %{
      world
      | actors:
          Map.new(world.actors, fn {number, actor} -> {number, %{actor | visible: false}} end)
    }

  @doc "Shows every actor standing in the current room: placed in a box, its costume started if new, not walking."
  @spec show_actors(World.t()) :: World.t()
  def show_actors(world) do
    world
    |> World.actors_in_room()
    |> Enum.reject(& &1.visible)
    |> Enum.reduce(world, &show(&2, &1.number))
  end

  @doc "Shows one actor in the current room."
  @spec show(World.t(), non_neg_integer()) :: World.t()
  def show(%World{room: 0} = world, _number), do: world

  def show(world, number) do
    actor = World.actor(world, number)

    world
    |> Walking.place(number, {actor.x, actor.y})
    |> World.update_actor(number, &initialised/1)
    |> World.update_actor(number, &%{&1 | visible: true, walk: nil})
  end

  defp initialised(%Actor{needs_init: true} = actor),
    do: %{Actor.start_frame(actor, actor.frames.init) | needs_init: false}

  defp initialised(actor), do: actor

  defp load(world, 0),
    do: %{
      world
      | room: 0,
        room_resource: 0,
        room_data: nil,
        room_objects: [],
        positions: %{},
        boxes: %{world.boxes | drawn: []},
        cycles: []
    }

  defp load(world, room) do
    resource = resource(world, room)
    data = Map.fetch!(Assets.get().rooms, resource)

    %{
      world
      | room: room,
        room_resource: resource,
        room_data: data,
        room_objects: data.objects,
        positions: %{},
        saved_text: %{},
        boxes: World.room_boxes(),
        camera: %{world.camera | x: 160, dest: 160, mode: :normal, moving_to_actor: false}
    }
    |> Palette.enter_room()
  end

  defp set_room_vars(ctx, 0),
    do: ctx |> Context.put_var(:room, 0) |> Context.put_var(:room_resource, 0)

  defp set_room_vars(ctx, room) do
    world = Context.world(ctx)

    ctx
    |> Context.put_var(:room, room)
    |> Context.put_var(:room_resource, world.room_resource)
    |> Context.put_var(:camera_min_x, div(World.screen_width(), 2))
    |> Context.put_var(:camera_max_x, world.room_data.width - div(World.screen_width(), 2))
  end

  defp arrive(ctx, actor, object) when is_integer(actor) and is_integer(object) and object != 0 do
    Context.update(ctx, fn world ->
      case Objects.walk_point(world, object) do
        nil ->
          world

        {point, facing} ->
          world |> place(actor, point) |> World.update_actor(actor, &Actor.face(&1, facing + 180))
      end
    end)
  end

  defp arrive(ctx, _actor, _object), do: ctx

  defp settle_arrival(ctx, actor, object)
       when is_integer(actor) and is_integer(object) and object != 0 do
    case Context.world(ctx) do
      %World{ego_positioned: false} = world ->
        case Objects.walk_point(world, object) do
          nil -> ctx
          {point, _facing} -> Context.update(ctx, &place(&1, actor, point))
        end

      _positioned ->
        ctx
    end
  end

  defp settle_arrival(ctx, _actor, _object), do: ctx

  defp place(world, actor, point) do
    world
    |> World.update_actor(actor, &%{&1 | room: world.room})
    |> Walking.place(actor, point)
  end

  defp run_scripts(ctx, first_var, own, second_var) do
    ctx
    |> start_var_script(first_var)
    |> start_own(own)
    |> start_var_script(second_var)
  end

  defp start_var_script(ctx, name) do
    case Context.var(ctx, name) do
      0 -> ctx
      number -> GrogVM.start_script(ctx, number, [])
    end
  end

  defp start_own(ctx, which) do
    world = Context.world(ctx)

    with room when room != 0 <- world.room_resource,
         %{^which => module} when module != nil <- Assets.get().room_code[room] do
      GrogVM.start_code(ctx, %{code: module, offset: 0, kind: :room}, 0, [])
    else
      _none -> ctx
    end
  end
end
