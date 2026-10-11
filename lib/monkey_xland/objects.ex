defmodule MonkeyXland.Objects do
  @moduledoc """
  Objects: their owners, states and classes, where each one is, which one is under a
  point, where an actor stands to use one, and the inventory.

  Classes are numbered 1 to 32; class 32 is "untouchable" (never found under the
  pointer). An object's state picks the picture it shows: state `n` shows its `n`th
  picture, state 0 shows none. An object with a parent is shown, and found under the
  pointer, only while its parent (and its parent's parent) are in the states it names.
  """

  import Bitwise

  alias MonkeyXland.{Actor, Assets, Boxes, World}
  alias MonkeyXland.Scumm.Room.Object

  @room_owner 15
  @untouchable 32

  @doc "Where an object is: `:inventory`, `:room` (the current room), or `:nowhere`."
  @spec where(World.t(), non_neg_integer()) :: :inventory | :room | :nowhere
  def where(world, number) do
    cond do
      World.object(world, number).owner != @room_owner and number in world.inventory -> :inventory
      World.room_object(world, number) != nil -> :room
      true -> :nowhere
    end
  end

  @doc "Sets an object's state."
  @spec put_state(World.t(), non_neg_integer(), integer()) :: World.t()
  def put_state(world, number, state),
    do: World.update_object(world, number, &%{&1 | state: state &&& 0xFF})

  @doc "Sets an object's owner; owner 0 also takes it out of the inventory list."
  @spec put_owner(World.t(), non_neg_integer(), integer()) :: World.t()
  def put_owner(world, number, 0),
    do: %{
      World.update_object(world, number, &%{&1 | owner: 0})
      | inventory: List.delete(world.inventory, number)
    }

  def put_owner(world, number, owner),
    do: World.update_object(world, number, &%{&1 | owner: owner &&& 0x0F})

  @doc "Whether object or actor `number` has class `class` (1 to 32)."
  @spec class?(World.t(), non_neg_integer(), 1..32) :: boolean()
  def class?(world, number, class),
    do: (World.object(world, number).classes &&& 1 <<< (class - 1)) != 0

  @doc "Sets (`value` true) or clears class `class`; class 0 clears every class."
  @spec put_class(World.t(), non_neg_integer(), 0..32, boolean()) :: World.t()
  def put_class(world, number, 0, _value),
    do: World.update_object(world, number, &%{&1 | classes: 0})

  def put_class(world, number, class, true),
    do: World.update_object(world, number, &%{&1 | classes: &1.classes ||| 1 <<< (class - 1)})

  def put_class(world, number, class, false),
    do:
      World.update_object(world, number, &%{&1 | classes: &1.classes &&& bnot(1 <<< (class - 1))})

  @doc "Applies `set_class` values: `0x80` in a value sets the class, its absence clears it, 0 clears all."
  @spec apply_classes(World.t(), non_neg_integer(), [integer()]) :: World.t()
  def apply_classes(world, number, values) do
    Enum.reduce(values, world, fn value, acc ->
      put_class(acc, number, value &&& 0x7F, (value &&& 0x80) != 0)
    end)
  end

  @doc "Whether every value of an `if_class_of_is` list matches: `0x80` set means the class must be set."
  @spec classes_match?(World.t(), non_neg_integer(), [integer()]) :: boolean()
  def classes_match?(world, number, values) do
    Enum.all?(values, fn value ->
      class?(world, number, value &&& 0x7F) == ((value &&& 0x80) != 0)
    end)
  end

  @doc "The topmost object under room point `{x, y}` that the player may touch, or 0."
  @spec at(World.t(), {integer(), integer()}) :: non_neg_integer()
  def at(world, {x, y}) do
    world.room_objects
    |> Enum.find(fn object ->
      object.number > 0 and not class?(world, object.number, @untouchable) and
        parents_shown?(world, object) and
        inside?(world, object, {x, y})
    end)
    |> then(&if(&1, do: &1.number, else: 0))
  end

  @doc "Where an object is placed in the room: `{x, y, width, height}`, moved by `draw_object … at`."
  @spec rect(World.t(), Object.t()) :: {integer(), integer(), integer(), integer()}
  def rect(world, %Object{number: number, x: x, y: y, width: width, height: height}) do
    {px, py} = Map.get(world.positions, number, {x, y})
    {px, py, width, height}
  end

  @doc "Where an actor stands to use object `number`, and the way it then faces (degrees)."
  @spec walk_point(World.t(), non_neg_integer()) :: {{integer(), integer()}, 0..359} | nil
  def walk_point(world, number) do
    case World.room_object(world, number) do
      nil -> nil
      object -> {walk_xy(world, object), Actor.facing(object.actor_dir &&& 3)}
    end
  end

  @doc "The position of an actor, or the walk point of an object, by number; `nil` when neither is placed."
  @spec position(World.t(), non_neg_integer()) :: {integer(), integer()} | nil
  def position(world, number) do
    case World.actor(world, number) do
      %Actor{x: x, y: y} -> {x, y}
      nil -> with({point, _facing} <- walk_point(world, number), do: point)
    end
  end

  @doc "The distance between two actors or objects as the original measured it: the larger of the two axes, 0xFF when one is missing."
  @spec distance(World.t(), non_neg_integer(), non_neg_integer()) :: non_neg_integer()
  def distance(world, first, second) do
    with {x1, y1} <- position(world, first),
         {x2, y2} <- second_position(world, first, second) do
      max(abs(x1 - x2), abs(y1 - y2))
    else
      _missing -> 0xFF
    end
  end

  @doc "Whether an object shows: it and every parent it hangs from are in the states that show it."
  @spec parents_shown?(World.t(), Object.t()) :: boolean()
  def parents_shown?(_world, %Object{parent: 0}), do: true

  def parents_shown?(world, %Object{parent: parent, parent_state: state}) do
    case Enum.at(world.room_objects, parent - 1) do
      nil ->
        true

      parent_object ->
        World.object(world, parent_object.number).state == state and
          parents_shown?(world, parent_object)
    end
  end

  @doc "Adds object `number` to the end of the inventory list when absent, owned by `owner`."
  @spec add_to_inventory(World.t(), non_neg_integer(), integer()) :: World.t()
  def add_to_inventory(world, number, owner) do
    inventory =
      if number in world.inventory, do: world.inventory, else: world.inventory ++ [number]

    %{put_owner(world, number, owner) | inventory: inventory}
  end

  @doc "How many inventory objects `owner` has."
  @spec inventory_count(World.t(), integer()) :: non_neg_integer()
  def inventory_count(world, owner),
    do: Enum.count(world.inventory, &(World.object(world, &1).owner == owner))

  @doc "The `index`th (from 1) inventory object `owner` has, or 0."
  @spec inventory_at(World.t(), integer(), integer()) :: non_neg_integer()
  def inventory_at(world, owner, index) do
    world.inventory
    |> Enum.filter(&(World.object(world, &1).owner == owner))
    |> Enum.at(index - 1, 0)
  end

  @doc "An object's name: one a script set, else the room's or its home room's."
  @spec name(World.t(), non_neg_integer()) :: binary()
  def name(world, number) do
    Map.get_lazy(world.object_names, number, fn ->
      home_object(world, number) |> then(&((&1 && &1.name) || ""))
    end)
  end

  @doc "The object as it is defined in whichever room holds it, or `nil`."
  @spec home_object(World.t(), non_neg_integer()) :: Object.t() | nil
  def home_object(world, number) do
    World.room_object(world, number) ||
      with room when room != nil <- Map.get(Assets.get().object_rooms, number),
           do: Enum.find(Assets.get().rooms[room].objects, &(&1.number == number))
  end

  defp second_position(world, first, second) do
    case {World.actor?(world, first), World.actor?(world, second), position(world, second)} do
      {true, false, point} when point != nil -> world |> Boxes.adjust(point) |> elem(0)
      {_first, _second, point} -> point
    end
  end

  defp walk_xy(world, %Object{number: number, x: x, y: y, walk_x: walk_x, walk_y: walk_y}) do
    case Map.get(world.positions, number) do
      nil -> {walk_x, walk_y}
      {px, py} -> {walk_x + px - x, walk_y + py - y}
    end
  end

  defp inside?(world, object, {px, py}) do
    {x, y, width, height} = rect(world, object)
    px >= x and px < x + width and py >= y and py < y + height
  end
end
