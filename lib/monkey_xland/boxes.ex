defmodule MonkeyXland.Boxes do
  @moduledoc """
  The current room's walk boxes: where a point lies, the nearest walkable point, the next
  box on the way from one box to another, the opening between two neighbouring boxes, and
  the scale an actor is drawn at in a box.

  Box 0 is never walked in. A box whose flags have `0x80` (invisible) or `0x40` (locked)
  set is skipped when choosing where to stand and when routing. Flags and scales scripts
  set with `matrix_ops` replace the room's own.
  """

  import Bitwise

  alias MonkeyXland.Scumm.Room
  alias MonkeyXland.Scumm.Room.{Box, BoxMatrix, ScaleSlot}
  alias MonkeyXland.World

  @invisible 0x80
  @locked 0x40
  @thresholds [30, 80, 0]

  @type point :: {integer(), integer()}

  @doc "The room's boxes, by number."
  @spec all(World.t()) :: %{non_neg_integer() => Box.t()}
  def all(%World{room_data: %Room{boxes: boxes}}),
    do: boxes |> Enum.with_index() |> Map.new(fn {box, number} -> {number, box} end)

  def all(%World{}), do: %{}

  @doc "A box's flags, as a script last set them."
  @spec flags(World.t(), non_neg_integer()) :: byte()
  def flags(%World{boxes: %{flags: overrides}} = world, number) do
    Map.get_lazy(overrides, number, fn ->
      world |> all() |> Map.get(number) |> then(&((&1 && &1.flags) || 0))
    end)
  end

  @doc "Whether `point` lies inside box `number` (its edges included)."
  @spec inside?(World.t(), non_neg_integer(), point()) :: boolean()
  def inside?(world, number, point) do
    case Map.get(all(world), number) do
      nil -> false
      box -> contains?(box, point)
    end
  end

  @doc "Whether `point` lies inside `box`."
  @spec contains?(Box.t(), point()) :: boolean()
  def contains?(%Box{} = box, point) do
    corners = corners(box)

    case area(corners) do
      0 -> segment_distance_squared(corners, point) <= 4
      _area -> convex_contains?(corners, point)
    end
  end

  @doc """
  Where an actor asked to stand at `point` ends up: the point itself in the box that
  holds it, or the nearest point of the nearest usable box. Returns the point and the box
  (0 when the room has no usable box).
  """
  @spec adjust(World.t(), point()) :: {point(), non_neg_integer()}
  def adjust(world, point) do
    usable = usable(world)
    Enum.find_value(@thresholds, {point, 0}, &nearest_within(usable, point, &1))
  end

  @doc "The box after `from` on the way to `to`, `to` itself when they are the same, `nil` when there is no way."
  @spec next_box(World.t(), non_neg_integer(), non_neg_integer()) :: non_neg_integer() | nil
  def next_box(_world, same, same), do: same

  def next_box(%World{boxes: %{routes: nil}, room_data: %Room{box_matrix: matrix}}, from, to) do
    case BoxMatrix.next_box(matrix, from, to) do
      {:ok, next} -> next
      :error -> nil
    end
  end

  def next_box(%World{boxes: %{routes: routes}}, from, to),
    do: routes |> Map.get(from, %{}) |> Map.get(to)

  @doc "Routes between boxes worked out again from which boxes touch, leaving locked boxes out."
  @spec route_table(World.t()) :: %{
          non_neg_integer() => %{non_neg_integer() => non_neg_integer()}
        }
  def route_table(world) do
    boxes =
      world |> all() |> Map.reject(fn {number, _box} -> number == 0 or locked?(world, number) end)

    neighbours =
      Map.new(boxes, fn {number, box} ->
        {number,
         for(
           {other, other_box} <- boxes,
           other != number,
           touching(box, other_box) != nil,
           do: other
         )}
      end)

    Map.new(boxes, fn {number, _box} -> {number, first_steps(number, neighbours)} end)
  end

  @doc """
  The opening to walk through from one box into the next, as the two ends of a segment:
  where their edges touch (a single point when they meet at a corner), or, for boxes
  that do not touch, the point of the next box nearest the first.
  """
  @spec gate(Box.t(), Box.t()) :: {point(), point()}
  def gate(%Box{} = from, %Box{} = to) do
    case touching(from, to) do
      nil -> nearest_pair(from, to)
      segment -> segment
    end
  end

  @doc "Where two boxes' edges touch, as a segment (both ends equal for a single point), or `nil`."
  @spec touching(Box.t(), Box.t()) :: {point(), point()} | nil
  def touching(%Box{} = from, %Box{} = to) do
    for edge <- edges(from), other <- edges(to), overlap = overlap(edge, other), overlap != nil do
      overlap
    end
    |> Enum.max_by(&segment_length_squared/1, fn -> nil end)
  end

  defp nearest_pair(from, to) do
    point =
      for edge <- edges(to), corner <- corners(from) do
        near = nearest_on_segment(edge, corner)
        {near, distance_squared(near, corner)}
      end
      |> Enum.min_by(&elem(&1, 1))
      |> elem(0)

    {point, point}
  end

  @doc "The point of segment `{a, b}` nearest to `point`."
  @spec nearest_on_segment({point(), point()}, point()) :: point()
  def nearest_on_segment({{ax, ay}, {bx, by}}, {px, py}) do
    {dx, dy} = {bx - ax, by - ay}
    length = dx * dx + dy * dy

    t =
      if length == 0,
        do: 0.0,
        else: min(max(((px - ax) * dx + (py - ay) * dy) / length, 0.0), 1.0)

    {round(ax + t * dx), round(ay + t * dy)}
  end

  @doc "The scale (1–255) an actor at row `y` in box `number` is drawn at."
  @spec scale(World.t(), non_neg_integer(), integer()) :: 1..255
  def scale(world, number, y) do
    raw =
      Map.get_lazy(world.boxes.scales, number, fn ->
        world |> all() |> Map.get(number) |> then(&((&1 && &1.scale) || 255))
      end)

    resolve_scale(world, raw, y)
  end

  defp resolve_scale(world, raw, y) when (raw &&& 0x8000) != 0 do
    slot = (raw &&& 0x7FFF) + 1
    world |> slot(slot) |> slot_scale(min(y, 199))
  end

  defp resolve_scale(_world, raw, _y), do: raw |> min(255) |> max(1)

  defp slot(
         %World{boxes: %{scale_slots: overrides}, room_data: %Room{scale_slots: slots}},
         number
       ),
       do: Map.get_lazy(overrides, number, fn -> Enum.at(slots, number - 1) end)

  defp slot_scale(nil, _y), do: 255

  defp slot_scale(%ScaleSlot{y1: same, y2: same, scale1: scale}, _y),
    do: scale |> min(255) |> max(1)

  defp slot_scale(%ScaleSlot{scale1: scale1, y1: y1, scale2: scale2, y2: y2}, y),
    do: (div((scale2 - scale1) * (y - y1), y2 - y1) + scale1) |> min(255) |> max(1)

  defp locked?(world, number), do: (flags(world, number) &&& (@invisible ||| @locked)) != 0

  defp usable(world) do
    world
    |> all()
    |> Enum.reject(fn {number, _box} ->
      number == 0 or (flags(world, number) &&& @invisible) != 0
    end)
    |> Enum.sort_by(&elem(&1, 0), :desc)
  end

  defp nearest_within(boxes, point, threshold) do
    case Enum.find(boxes, fn {_number, box} -> contains?(box, point) end) do
      {number, _box} -> {point, number}
      nil -> nearest_box(boxes, point, threshold)
    end
  end

  defp nearest_box(boxes, point, threshold) do
    best =
      boxes
      |> Enum.map(fn {number, box} -> {number, closest_point(box, point)} end)
      |> Enum.min_by(fn {_number, {_point, distance}} -> distance end, fn -> nil end)

    case best do
      {number, {found, distance}} when threshold == 0 or threshold * threshold >= distance ->
        {found, number}

      _none ->
        nil
    end
  end

  defp closest_point(box, point) do
    box
    |> edges()
    |> Enum.map(fn edge -> nearest_on_segment(edge, point) end)
    |> Enum.map(fn found -> {found, distance_squared(found, point)} end)
    |> Enum.min_by(&elem(&1, 1))
  end

  defp first_steps(from, neighbours) do
    from
    |> breadth_first(neighbours, :queue.from_list([{from, nil}]), %{from => nil})
    |> Map.delete(from)
  end

  defp breadth_first(from, neighbours, queue, seen) do
    case :queue.out(queue) do
      {:empty, _queue} -> seen
      {{:value, {box, first}}, queue} -> visit(from, neighbours, box, first, queue, seen)
    end
  end

  defp visit(from, neighbours, box, first, queue, seen) do
    fresh = neighbours |> Map.get(box, []) |> Enum.reject(&is_map_key(seen, &1))
    step = fn next -> if box == from, do: next, else: first end
    seen = Enum.reduce(fresh, seen, &Map.put(&2, &1, step.(&1)))
    queue = Enum.reduce(fresh, queue, &:queue.in({&1, step.(&1)}, &2))
    breadth_first(from, neighbours, queue, seen)
  end

  defp corners(%Box{upper_left: ul, upper_right: ur, lower_right: lr, lower_left: ll}),
    do: [ul, ur, lr, ll]

  defp edges(box) do
    [ul, ur, lr, ll] = corners(box)
    [{ul, ur}, {ur, lr}, {lr, ll}, {ll, ul}]
  end

  defp area(corners) do
    corners
    |> Enum.zip(tl(corners) ++ [hd(corners)])
    |> Enum.reduce(0, fn {{x1, y1}, {x2, y2}}, sum -> sum + x1 * y2 - x2 * y1 end)
  end

  defp convex_contains?(corners, {px, py}) do
    crosses =
      corners
      |> Enum.zip(tl(corners) ++ [hd(corners)])
      |> Enum.map(fn {{x1, y1}, {x2, y2}} -> (x2 - x1) * (py - y1) - (y2 - y1) * (px - x1) end)
      |> Enum.reject(&(&1 == 0))

    Enum.all?(crosses, &(&1 > 0)) or Enum.all?(crosses, &(&1 < 0))
  end

  defp segment_distance_squared(corners, point) do
    corners
    |> Enum.zip(tl(corners) ++ [hd(corners)])
    |> Enum.map(fn edge -> edge |> nearest_on_segment(point) |> distance_squared(point) end)
    |> Enum.min()
  end

  defp overlap({a1, a2} = edge, {b1, b2}) do
    near_b1 = nearest_on_segment(edge, b1)
    near_b2 = nearest_on_segment(edge, b2)
    near_a1 = nearest_on_segment({b1, b2}, a1)
    near_a2 = nearest_on_segment({b1, b2}, a2)

    touching =
      [{near_b1, b1}, {near_b2, b2}, {a1, near_a1}, {a2, near_a2}]
      |> Enum.filter(fn {on_a, on_b} -> distance_squared(on_a, on_b) <= 4 end)
      |> Enum.map(&elem(&1, 0))
      |> Enum.uniq()

    farthest_pair(touching)
  end

  defp farthest_pair([]), do: nil
  defp farthest_pair([point]), do: {point, point}

  defp farthest_pair(points) do
    for(a <- points, b <- points, a < b, do: {a, b})
    |> Enum.max_by(&segment_length_squared/1, fn -> nil end)
  end

  defp segment_length_squared({a, b}), do: distance_squared(a, b)

  defp distance_squared({x1, y1}, {x2, y2}), do: (x1 - x2) * (x1 - x2) + (y1 - y2) * (y1 - y2)
end
