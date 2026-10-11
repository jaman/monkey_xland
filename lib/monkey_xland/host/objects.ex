defmodule MonkeyXland.Host.Objects do
  @moduledoc """
  Script operations on objects: states, owners, classes, pictures shown, names, the
  inventory, what lies under a point, and objects carried in from other rooms.
  """

  alias MonkeyXland.{Assets, Context, Message, Objects, World}

  @untouchable 32

  @doc "Runs one object operation."
  @spec op(GrogVM.Ctx.t(), tuple()) ::
          {:ok, GrogVM.Ctx.t()} | {:ok, integer() | boolean(), GrogVM.Ctx.t()}
  def op(ctx, {:set_state, object, state}),
    do: {:ok, Context.update(ctx, &Objects.put_state(&1, object, state))}

  def op(ctx, {:get_object_state, object}),
    do: {:ok, World.object(Context.world(ctx), object).state, ctx}

  def op(ctx, {:get_object_owner, object}),
    do: {:ok, World.object(Context.world(ctx), object).owner, ctx}

  def op(ctx, {:if_state, object, state}),
    do: {:ok, World.object(Context.world(ctx), object).state == state, ctx}

  def op(ctx, {:if_not_state, object, state}),
    do: {:ok, World.object(Context.world(ctx), object).state != state, ctx}

  def op(ctx, {:set_class, object, classes}),
    do: {:ok, Context.update(ctx, &Objects.apply_classes(&1, object, classes))}

  def op(ctx, {:if_class_of_is, object, classes}),
    do: {:ok, Objects.classes_match?(Context.world(ctx), object, classes), ctx}

  def op(ctx, {:find_object, x, y}), do: {:ok, Objects.at(Context.world(ctx), {x, y}), ctx}

  def op(ctx, {:find_inventory, owner, index}),
    do: {:ok, Objects.inventory_at(Context.world(ctx), owner, index), ctx}

  def op(ctx, {:get_inventory_count, owner}),
    do: {:ok, Objects.inventory_count(Context.world(ctx), owner), ctx}

  def op(ctx, {:set_owner_of, object, owner}) do
    ctx |> Context.update(&Objects.put_owner(&1, object, owner)) |> inventory_script(0) |> ok()
  end

  def op(ctx, {:pickup_object, object, room}), do: pickup(ctx, object, room)
  def op(ctx, {:pickup_object_old, object}), do: pickup(ctx, object, 0)

  def op(ctx, {:draw_object, object, how}), do: {:ok, Context.update(ctx, &draw(&1, object, how))}

  def op(ctx, {:get_verb_entrypoint, object, verb}),
    do: {:ok, entry(Context.world(ctx), object, verb), ctx}

  def op(ctx, {:set_object_name, object, message}),
    do:
      {:ok,
       Context.update(
         ctx,
         &%{&1 | object_names: Map.put(&1.object_names, object, Message.plain(&1, message))}
       )}

  def op(ctx, {:resource_routines, {:load_object, [room, object]}}),
    do: {:ok, Context.update(ctx, &carry_in(&1, object, room))}

  def op(ctx, {:resource_routines, _other}), do: {:ok, ctx}

  defp ok(ctx), do: {:ok, ctx}

  defp pickup(ctx, object, _room) do
    ego = Context.var(ctx, :ego)

    ctx
    |> Context.update(fn world ->
      world
      |> Objects.add_to_inventory(object, ego)
      |> Objects.put_class(object, @untouchable, true)
      |> Objects.put_state(object, 1)
    end)
    |> inventory_script(1)
    |> ok()
  end

  defp inventory_script(ctx, argument) do
    case Context.var(ctx, :inventory_script) do
      0 -> ctx
      script -> GrogVM.start_script(ctx, script, [argument])
    end
  end

  defp draw(world, object, how) do
    case World.room_object(world, object) do
      nil -> world
      found -> shown(moved(world, found, how), found, state_of(how))
    end
  end

  defp moved(world, object, {:at, [x, y]}) when x != 0xFF,
    do: %{world | positions: Map.put(world.positions, object.number, {x * 8, y * 8})}

  defp moved(world, _object, _how), do: world

  defp state_of({:state, [state]}), do: state
  defp state_of(_how), do: 1

  defp shown(world, object, state) do
    rect = Objects.rect(world, object)

    world.room_objects
    |> Enum.filter(&(&1.number != object.number and Objects.rect(world, &1) == rect))
    |> Enum.reduce(world, &Objects.put_state(&2, &1.number, 0))
    |> Objects.put_state(object.number, state)
  end

  defp entry(world, object, verb) do
    with true <- Objects.where(world, object) != :nowhere,
         room when room != nil <- Map.get(Assets.get().object_rooms, object),
         {_module, verbs} <- get_in(Assets.get().room_code, [room, :objects, object]),
         offset when offset != nil <- Map.get(verbs, verb) || Map.get(verbs, 0xFF) do
      offset + 1
    else
      _none -> 0
    end
  end

  defp carry_in(world, object, room) do
    with nil <- World.room_object(world, object),
         %{objects: objects} <- Map.get(Assets.get().rooms, room),
         found when found != nil <- Enum.find(objects, &(&1.number == object)) do
      %{world | room_objects: world.room_objects ++ [found]}
    else
      _present_or_missing -> world
    end
  end
end
