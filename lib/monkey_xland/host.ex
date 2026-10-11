defmodule MonkeyXland.Host do
  @moduledoc """
  The Secret of Monkey Island's side of `GrogVM.Host`: finds the code a script number or
  object verb starts, and runs every operation scripts ask of the game, each in the
  module for its subject.
  """

  @behaviour GrogVM.Host

  alias MonkeyXland.{Assets, Context}
  alias MonkeyXland.Host.{Actors, Audio, Interface, Objects, Rooms}

  @global_limit 200

  @actors ~w(put_actor put_actor_in_room put_actor_at_object walk_actor_to walk_actor_to_actor
    walk_actor_to_object face_actor animate_actor actor_ops actor_follow_camera get_actor_room
    get_actor_elevation get_actor_costume get_actor_width get_actor_scale get_actor_walk_box
    get_anim_counter get_actor_facing get_actor_moving get_actor_x get_actor_y get_dist
    get_closest_obj_actor actor_from_pos is_actor_in_box)a
  @objects ~w(set_state get_object_state get_object_owner if_state if_not_state set_class
    if_class_of_is find_object find_inventory get_inventory_count set_owner_of pickup_object
    pickup_object_old draw_object get_verb_entrypoint set_object_name resource_routines)a
  @rooms ~w(load_room load_room_with_ego set_camera_at pan_camera_to room_ops matrix_ops
    pseudo_room lights old_room_effect draw_box)a
  @interface ~w(print print_ego string_ops get_string_width cursor_command verb_ops
    save_restore_verbs do_sentence wait)a
  @audio ~w(start_sound start_music stop_sound stop_music is_sound_running sound_kludge system_ops)a

  @handlers Map.new(@actors, &{&1, Actors})
            |> Map.merge(Map.new(@objects, &{&1, Objects}))
            |> Map.merge(Map.new(@rooms, &{&1, Rooms}))
            |> Map.merge(Map.new(@interface, &{&1, Interface}))
            |> Map.merge(Map.new(@audio, &{&1, Audio}))

  @impl true
  def op(ctx, operation), do: Map.fetch!(@handlers, elem(operation, 0)).op(ctx, operation)

  @impl true
  def code(_ctx, {:script, number}) when number < @global_limit do
    case Map.get(Assets.get().globals, number) do
      nil -> :none
      module -> {:ok, %{code: module, offset: 0, kind: :global}}
    end
  end

  def code(ctx, {:script, number}) do
    room = Context.world(ctx).room_resource

    case get_in(Assets.get().room_code, [room, :locals, number]) do
      nil -> :none
      module -> {:ok, %{code: module, offset: 0, kind: :local}}
    end
  end

  def code(ctx, {:object, object, verb}) do
    world = Context.world(ctx)

    with where when where != :nowhere <- MonkeyXland.Objects.where(world, object),
         room when room != nil <- Map.get(Assets.get().object_rooms, object),
         {module, verbs} <- get_in(Assets.get().room_code, [room, :objects, object]),
         offset when offset != nil <- Map.get(verbs, verb) || Map.get(verbs, 0xFF) do
      {:ok, %{code: module, offset: offset, kind: kind(where)}}
    else
      _none -> :none
    end
  end

  defp kind(:inventory), do: :inventory
  defp kind(:room), do: :object
end
