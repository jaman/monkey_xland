defmodule MonkeyXland.Host.Interface do
  @moduledoc """
  Script operations on what the player sees and does: printing and talking, strings,
  the cursor and the font, verbs, sentences, and waiting for actors, messages, the
  camera and sentences.

  `print` writes to a text slot chosen by its actor number: 254 is slot 1 (text drawn
  straight onto the screen), 253 slot 2, 252 slot 3, any other actor slot 0 (talking,
  or the narrator for 255). Settings given without text become the slot's defaults;
  settings given with text apply to that text only.
  """

  alias MonkeyXland.{Assets, Context, Message, Talk, Verbs, Walking, World}
  alias MonkeyXland.Scumm.Charset

  @doc "Runs one interface operation."
  @spec op(GrogVM.Ctx.t(), tuple()) ::
          {:ok, GrogVM.Ctx.t()} | {:ok, integer(), GrogVM.Ctx.t()} | {:retry, GrogVM.Ctx.t()}
  def op(ctx, {:print, actor, ops}), do: {:ok, print(ctx, actor, ops)}
  def op(ctx, {:print_ego, ops}), do: {:ok, print(ctx, Context.var(ctx, :ego), ops)}

  def op(ctx, {:string_ops, {:get_char, [string, index]}}),
    do: {:ok, char_at(Context.world(ctx), string, index), ctx}

  def op(ctx, {:string_ops, {name, args}}),
    do: {:ok, Context.update(ctx, &string_op(&1, name, args))}

  def op(ctx, {:get_string_width, string}) do
    world = Context.world(ctx)
    {:ok, world.charset |> Assets.charset() |> width(Map.get(world.strings, string, "")), ctx}
  end

  def op(ctx, {:cursor_command, {name, args}}),
    do: {:ok, ctx |> Context.update(&cursor_op(&1, name, args)) |> cursor_vars()}

  def op(ctx, {:verb_ops, verb, ops}),
    do: {:ok, Context.update(ctx, &Verbs.apply_ops(&1, verb, ops))}

  def op(ctx, {:save_restore_verbs, {kind, [first, last, save_id]}}),
    do: {:ok, Context.update(ctx, &Verbs.save_restore(&1, kind, first, last, save_id))}

  def op(ctx, {:do_sentence, :stop}) do
    ctx = Context.update(ctx, &%{&1 | sentences: []})
    {:ok, GrogVM.stop_script(ctx, Context.var(ctx, :sentence_script))}
  end

  def op(ctx, {:do_sentence, verb, object_a, object_b}),
    do:
      {:ok, Context.update(ctx, &%{&1 | sentences: &1.sentences ++ [{verb, object_a, object_b}]})}

  def op(ctx, {:wait, {:actor, [number]}}),
    do: wait_while(ctx, Walking.moving?(Context.world(ctx), number))

  def op(ctx, {:wait, {:message, []}}), do: wait_while(ctx, Context.world(ctx).message != nil)
  def op(ctx, {:wait, {:camera, []}}), do: wait_while(ctx, camera_moving?(Context.world(ctx)))

  def op(ctx, {:wait, {:sentence, []}}),
    do:
      wait_while(
        ctx,
        Context.world(ctx).sentences != [] or
          GrogVM.running?(ctx, Context.var(ctx, :sentence_script))
      )

  defp wait_while(ctx, true), do: {:retry, ctx}
  defp wait_while(ctx, false), do: {:ok, ctx}

  defp camera_moving?(%World{camera: %{x: x, dest: dest}}), do: div(x, 8) != div(dest, 8)

  defp print(ctx, actor, ops) do
    slot = slot(actor)
    world = Context.world(ctx)
    settings = Map.fetch!(world.text, slot)
    {settings, message} = Enum.reduce(ops, {settings, nil}, &setting/2)
    printed(ctx, slot, actor, settings, message)
  end

  defp printed(ctx, slot, _actor, settings, nil),
    do: Context.update(ctx, &%{&1 | text: Map.put(&1.text, slot, settings)})

  defp printed(ctx, 0, actor, settings, message),
    do:
      Talk.say(
        ctx,
        actor,
        %{settings | charset: Context.world(ctx).charset},
        message,
        MonkeyXland.Voices.for_message(ctx, message)
      )

  defp printed(ctx, 3, _actor, settings, message),
    do: Talk.say(ctx, 0xFF, %{settings | charset: Context.world(ctx).charset}, message)

  defp printed(ctx, slot, _actor, settings, message) do
    Context.update(ctx, fn world ->
      key = {settings.x, settings.y}

      text = %{
        settings: %{settings | charset: world.charset},
        pages: Message.pages(world, message, settings.color)
      }

      %{world | saved_text: Map.put(world.saved_text, {slot, key}, text)}
    end)
  end

  defp slot(254), do: 1
  defp slot(253), do: 2
  defp slot(252), do: 3
  defp slot(_actor), do: 0

  defp setting({:at, [x, y]}, {settings, message}), do: {%{settings | x: x, y: y}, message}
  defp setting({:color, [color]}, {settings, message}), do: {%{settings | color: color}, message}

  defp setting({:clipped, [right]}, {settings, message}),
    do: {%{settings | right: right}, message}

  defp setting({:erase, _args}, acc), do: acc
  defp setting({:center, []}, {settings, message}), do: {%{settings | center: true}, message}
  defp setting({:left, []}, {settings, message}), do: {%{settings | center: false}, message}
  defp setting({:overhead, []}, {settings, message}), do: {%{settings | overhead: true}, message}
  defp setting({:voice, _args}, acc), do: acc
  defp setting({:text, [text]}, {settings, _message}), do: {settings, text}

  defp string_op(world, :load, [string, message]),
    do: put_string(world, string, Message.plain(world, message))

  defp string_op(world, :copy, [to, from]),
    do: put_string(world, to, Map.get(world.strings, from, ""))

  defp string_op(world, :create, [string, size]),
    do: put_string(world, string, :binary.copy(<<0>>, max(size, 0)))

  defp string_op(world, :set_char, [string, index, char]),
    do: put_string(world, string, set_char(Map.get(world.strings, string, ""), index, char))

  defp put_string(world, string, bytes),
    do: %{world | strings: Map.put(world.strings, string, bytes)}

  defp set_char(bytes, index, char) when index >= 0 and index < byte_size(bytes),
    do:
      binary_part(bytes, 0, index) <>
        <<char>> <> binary_part(bytes, index + 1, byte_size(bytes) - index - 1)

  defp set_char(bytes, _index, _char), do: bytes

  defp char_at(world, string, index) do
    bytes = Map.get(world.strings, string, "")
    if index >= 0 and index < byte_size(bytes), do: :binary.at(bytes, index), else: 0
  end

  defp width(nil, _text), do: 0
  defp width(%Charset{} = charset, text), do: Charset.width(charset, text)

  defp cursor_op(world, :cursor_on, []), do: put_cursor(world, :state, 1)
  defp cursor_op(world, :cursor_off, []), do: put_cursor(world, :state, 0)
  defp cursor_op(world, :userput_on, []), do: put_cursor(world, :userput, 1)
  defp cursor_op(world, :userput_off, []), do: put_cursor(world, :userput, 0)

  defp cursor_op(world, :cursor_soft_on, []),
    do: put_cursor(world, :state, world.cursor.state + 1)

  defp cursor_op(world, :cursor_soft_off, []),
    do: put_cursor(world, :state, world.cursor.state - 1)

  defp cursor_op(world, :userput_soft_on, []),
    do: put_cursor(world, :userput, world.cursor.userput + 1)

  defp cursor_op(world, :userput_soft_off, []),
    do: put_cursor(world, :userput, world.cursor.userput - 1)

  defp cursor_op(world, :image, [_object, _room]), do: world
  defp cursor_op(world, :hotspot, [_cursor, x, y]), do: put_cursor(world, :hotspot, {x, y})
  defp cursor_op(world, :cursor, [shape]), do: put_cursor(world, :shape, shape)

  defp cursor_op(world, :charset, [charset]),
    do: %{
      world
      | charset: charset,
        text:
          Map.new(world.text, fn {slot, settings} -> {slot, %{settings | charset: charset}} end)
    }

  defp cursor_op(world, :charset_colors, [colors]),
    do: %{world | charset_colors: Map.put(world.charset_colors, world.charset, colors)}

  defp put_cursor(world, key, value), do: %{world | cursor: Map.put(world.cursor, key, value)}

  defp cursor_vars(ctx) do
    cursor = Context.world(ctx).cursor

    ctx
    |> Context.put_var(:cursor_state, cursor.state)
    |> Context.put_var(:userput, cursor.userput)
  end
end
