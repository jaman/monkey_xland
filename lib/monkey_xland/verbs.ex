defmodule MonkeyXland.Verbs do
  @moduledoc """
  The verbs on screen: each is text (or an object's picture) at a screen position, with
  a colour for when it is off, highlighted under the pointer, or dimmed, and a key that
  chooses it.

  `mode` is 0 (hidden), 1 (shown) or 2 (dimmed). A verb a script saved (`save_id` not
  0) is hidden until restored.
  """

  alias MonkeyXland.{Assets, Message, World}
  alias MonkeyXland.Scumm.Charset

  @type verb :: %{
          id: non_neg_integer(),
          x: integer(),
          y: integer(),
          name: binary() | nil,
          image: {non_neg_integer(), non_neg_integer()} | nil,
          color: byte(),
          hi_color: byte(),
          dim_color: byte(),
          back_color: byte(),
          key: byte(),
          center: boolean(),
          mode: 0..2,
          save_id: non_neg_integer(),
          charset: non_neg_integer()
        }

  @doc "A new verb with SCUMM v5's defaults, drawn in `charset`."
  @spec new(non_neg_integer(), non_neg_integer()) :: verb()
  def new(id, charset) do
    %{
      id: id,
      x: 0,
      y: 0,
      name: nil,
      image: nil,
      color: 2,
      hi_color: 0,
      dim_color: 8,
      back_color: 0,
      key: 0,
      center: false,
      mode: 0,
      save_id: 0,
      charset: charset
    }
  end

  @doc "Runs a `verb_ops` instruction's sub-operations on verb `id`."
  @spec apply_ops(World.t(), non_neg_integer(), [{atom(), list()}]) :: World.t()
  def apply_ops(world, id, ops), do: Enum.reduce(ops, world, &apply_op(&2, id, &1))

  @doc "Saves (`:save`), restores (`:restore`) or deletes (`:delete`) the verbs `first..last` under `save_id`."
  @spec save_restore(World.t(), :save | :restore | :delete, integer(), integer(), integer()) ::
          World.t()
  def save_restore(world, :save, first, last, save_id) do
    update_range(world, first, last, &(&1.save_id == 0), &%{&1 | save_id: save_id})
  end

  def save_restore(world, :restore, first, last, save_id) do
    update_range(world, first, last, &(&1.save_id == save_id), &%{&1 | save_id: 0})
  end

  def save_restore(world, :delete, first, last, save_id) do
    doomed = for {id, verb} <- world.verbs, id in first..last//1, verb.save_id == save_id, do: id
    %{world | verbs: Map.drop(world.verbs, doomed)}
  end

  @doc "The verb under screen point `{x, y}` that the player may choose, or `nil`."
  @spec at(World.t(), {integer(), integer()}) :: verb() | nil
  def at(world, {x, y}) do
    world.verbs
    |> Map.values()
    |> Enum.sort_by(& &1.id, :desc)
    |> Enum.find(fn verb ->
      verb.mode != 0 and verb.save_id == 0 and verb.id != 0 and inside?(rect(verb), {x, y})
    end)
  end

  @doc "The verb whose key is `key`, shown and not saved, or `nil`."
  @spec with_key(World.t(), byte()) :: verb() | nil
  def with_key(world, key),
    do: Enum.find(Map.values(world.verbs), &(&1.key == key and &1.mode != 0 and &1.save_id == 0))

  @doc "Where a verb is drawn on screen: `{left, top, right, bottom}`."
  @spec rect(verb()) :: {integer(), integer(), integer(), integer()}
  def rect(%{name: name, x: x, y: y, charset: charset, center: center}) do
    case Assets.charset(charset) do
      nil -> {x, y, x, y}
      font -> text_rect(font, name || "", x, y, center)
    end
  end

  defp text_rect(%Charset{height: height} = font, name, x, y, center) do
    width = Charset.width(font, name)
    left = if center, do: x - div(width, 2), else: x
    {left, y, left + width, y + height}
  end

  defp inside?({left, top, right, bottom}, {x, y}),
    do: x >= left and x < right and y >= top and y < bottom

  defp update_range(world, first, last, select?, change) do
    verbs =
      Map.new(world.verbs, fn {id, verb} ->
        {id, if(id in first..last//1 and select?.(verb), do: change.(verb), else: verb)}
      end)

    %{world | verbs: verbs}
  end

  defp apply_op(world, id, {:new, []}),
    do: %{world | verbs: Map.put(world.verbs, id, new(id, world.charset))}

  defp apply_op(world, id, {:delete, []}), do: %{world | verbs: Map.delete(world.verbs, id)}

  defp apply_op(world, id, op),
    do: %{
      world
      | verbs:
          Map.put(
            world.verbs,
            id,
            change(world, Map.get_lazy(world.verbs, id, fn -> new(id, world.charset) end), op)
          )
    }

  defp change(world, verb, {:name, [message]}),
    do: %{verb | name: Message.plain(world, message), image: nil}

  defp change(_world, verb, {:image, [object]}), do: %{verb | image: {object, 0}}

  defp change(_world, verb, {:image_from_object, [object, room]}),
    do: %{verb | image: {object, room}}

  defp change(world, verb, {:name_from_string, [string]}),
    do: %{verb | name: world.strings |> Map.get(string, "") |> Message.unpadded(), image: nil}

  defp change(_world, verb, {:color, [color]}), do: %{verb | color: color}
  defp change(_world, verb, {:hi_color, [color]}), do: %{verb | hi_color: color}
  defp change(_world, verb, {:dim_color, [color]}), do: %{verb | dim_color: color}
  defp change(_world, verb, {:back_color, [color]}), do: %{verb | back_color: color}
  defp change(_world, verb, {:at, [x, y]}), do: %{verb | x: x, y: y}
  defp change(_world, verb, {:on, []}), do: %{verb | mode: 1}
  defp change(_world, verb, {:off, []}), do: %{verb | mode: 0}
  defp change(_world, verb, {:dim, []}), do: %{verb | mode: 2}
  defp change(_world, verb, {:key, [key]}), do: %{verb | key: key}
  defp change(_world, verb, {:center, []}), do: %{verb | center: true}
end
