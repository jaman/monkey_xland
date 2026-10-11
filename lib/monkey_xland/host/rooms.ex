defmodule MonkeyXland.Host.Rooms do
  @moduledoc """
  Script operations on rooms: changing room, the camera, the screen's layout, the
  palette and its brightness, walk boxes and their routes, scale slots, room-number
  mapping, and boxes drawn straight onto the screen.
  """

  alias MonkeyXland.{Boxes, Camera, Context, Palette, Scene, Shake, Walking, World}
  alias MonkeyXland.Scumm.Room.ScaleSlot

  @doc "Runs one room operation."
  @spec op(GrogVM.Ctx.t(), tuple()) :: {:ok, GrogVM.Ctx.t()}
  def op(ctx, {:load_room, room}), do: {:ok, Scene.start(ctx, room)}

  def op(ctx, {:load_room_with_ego, object, room, x, y}) do
    ego = Context.var(ctx, :ego)

    ctx
    |> Context.update(
      &World.update_actor(&1, ego, fn actor -> %{actor | room: room, x: 0, y: 0} end)
    )
    |> Context.put_var(:walk_to_object, object)
    |> Scene.start(room, ego, object)
    |> Context.put_var(:walk_to_object, 0)
    |> follow_ego(ego)
    |> walk_ego(ego, x, y)
    |> then(&{:ok, &1})
  end

  def op(ctx, {:set_camera_at, x}), do: {:ok, Camera.set_at(ctx, x)}
  def op(ctx, {:pan_camera_to, x}), do: {:ok, Camera.pan_to(ctx, x)}
  def op(ctx, {:room_ops, {name, args}}), do: {:ok, room_op(ctx, name, args)}

  def op(ctx, {:matrix_ops, {name, args}}),
    do: {:ok, Context.update(ctx, &matrix_op(&1, name, args))}

  def op(ctx, {:pseudo_room, room, numbers}) do
    mapped = for number <- numbers, number >= 0x80, into: %{}, do: {number - 0x80, room}
    {:ok, Context.update(ctx, &%{&1 | pseudo_rooms: Map.merge(&1.pseudo_rooms, mapped)})}
  end

  def op(ctx, {:lights, lights, _x_strips, 0}),
    do:
      {:ok,
       ctx |> Context.put_var(:current_lights, lights) |> Context.update(&%{&1 | lights: lights})}

  def op(ctx, {:lights, _lights, _x_strips, _mode}), do: {:ok, ctx}

  def op(ctx, {:old_room_effect, {:effect, [effect]}}),
    do: {:ok, Context.update(ctx, &put_in(&1.effect.kind, effect))}

  def op(ctx, {:old_room_effect, _other}), do: {:ok, ctx}

  def op(ctx, {:draw_box, x, y, x2, y2, color}),
    do:
      {:ok,
       Context.update(
         ctx,
         &update_in(
           &1.boxes.drawn,
           fn drawn -> drawn ++ [{min(x, x2), min(y, y2), max(x, x2), max(y, y2), color}] end
         )
       )}

  defp follow_ego(ctx, ego) do
    world = Context.world(ctx)
    x = World.actor(world, ego).x
    ctx |> Context.update(&%{&1 | camera: %{&1.camera | x: x, dest: x}}) |> Camera.follow(ego)
  end

  defp walk_ego(ctx, _ego, x, _y) when x in [-1, 0x7FFF], do: ctx
  defp walk_ego(ctx, ego, x, y), do: Context.update(ctx, &Walking.start(&1, ego, {x, y}, nil))

  defp room_op(ctx, :scroll, [low, high]) do
    width = Context.world(ctx).room_data.width
    half = div(World.screen_width(), 2)
    clamp = fn value -> value |> max(half) |> min(width - half) end

    ctx
    |> Context.put_var(:camera_min_x, clamp.(low))
    |> Context.put_var(:camera_max_x, clamp.(high))
  end

  defp room_op(ctx, :screen, [top, bottom]),
    do: Context.update(ctx, &%{&1 | screen: %{&1.screen | top: top, height: bottom - top}})

  defp room_op(ctx, :palette, [red, green, blue, index]),
    do: Context.update(ctx, &Palette.set_color(&1, index, red, green, blue))

  defp room_op(ctx, :shake_on, []), do: Context.update(ctx, &Shake.on/1)
  defp room_op(ctx, :shake_off, []), do: Context.update(ctx, &Shake.off/1)

  defp room_op(ctx, :scale, [scale1, y1, scale2, y2, slot]),
    do:
      Context.update(
        ctx,
        &put_in(&1.boxes.scale_slots[slot], %ScaleSlot{
          scale1: scale1,
          y1: y1,
          scale2: scale2,
          y2: y2
        })
      )

  defp room_op(ctx, :intensity, [scale, first, last]),
    do: Context.update(ctx, &Palette.intensity(&1, scale, scale, scale, first, last))

  defp room_op(ctx, :rgb_intensity, [red, green, blue, first, last]),
    do: Context.update(ctx, &Palette.intensity(&1, red, green, blue, first, last))

  defp room_op(ctx, :effect, [effect]), do: Context.update(ctx, &put_in(&1.effect.kind, effect))

  defp room_op(ctx, :cycle_delay, [id, delay]),
    do: Context.update(ctx, &Palette.set_cycle_delay(&1, id, delay))

  defp room_op(ctx, :save_load, [mode, slot]),
    do: Context.update(ctx, &World.emit(&1, {:save_load, mode, slot}))

  defp room_op(ctx, _name, _args), do: ctx

  defp matrix_op(world, :box_flags, [box, flags]),
    do: put_in(world.boxes.flags[box], flags)

  defp matrix_op(world, :box_scale, [box, scale]),
    do: put_in(world.boxes.scales[box], scale)

  defp matrix_op(world, :create_box_matrix, []),
    do: put_in(world.boxes.routes, Boxes.route_table(world))
end
