defmodule MonkeyXland.Engine do
  @moduledoc """
  One SCUMM frame of the game, in the order SCUMM v5 runs it:

    1. the timers (variables 11–13 and 47) advance by the frame's jiffies, `timer` (46)
       becomes them, and the music timer (14) advances while music plays,
    2. the message on screen counts down,
    3. the mouse variables are set: 44 and 45 on the screen, 20 and 21 in the room,
    4. every script due runs,
    5. the player's input goes to the verb script (variable 32) as
       `[area, value, button]`: area 1 a verb (value its number, 0 for the verb area
       outside any verb), 2 the room, 4 a key; button 1 left, 2 right. The key in
       variable 24 skips a cutscene, the key in variable 57 skips the page of text shown,
    6. the newest queued sentence runs through the sentence script (variable 33) when
       that script is free,
    7. actors walk, the camera moves, costumes animate, palettes cycle, sounds time out,
       the screen shake moves on.

  `new/1` boots the game: the engine variables a CD drive and a VGA machine set are set —
  among them variable 74, the size of the CD's track B, which the game checks — and
  global script 1 runs with the boot arguments.
  """

  alias MonkeyXland.{
    Actor,
    Camera,
    Context,
    Host,
    Palette,
    Shake,
    Sounds,
    Talk,
    Vars,
    Verbs,
    Walking,
    World
  }

  @type input ::
          {:click, {integer(), integer()}, :left | :right}
          | {:key, non_neg_integer()}
          | {:pointer, {integer(), integer()}}

  @doc "A game at power-on, its boot script run."
  @spec new(keyword()) :: GrogVM.Ctx.t()
  def new(opts \\ []) do
    ctx =
      GrogVM.new(Host, World.new(),
        config: Vars.machine_config(),
        seed: Keyword.get(opts, :seed, :erlang.unique_integer([:positive]))
      )

    ctx
    |> Context.put_var(:machine_speed, 0x7FFF)
    |> Context.put_var(:sound_card, 3)
    |> Context.put_var(:video_mode, 0x13)
    |> Context.put_var(:fixed_disk, 1)
    |> Context.put_var(:heap_space, 1400)
    |> Context.put_var(:memory_performance, 100)
    |> Context.put_var(:video_performance, 100)
    |> Context.put_var(:talk_stop_key, ?.)
    |> Context.put_var(:cutscene_exit_key, 27)
    |> Context.put_var(:char_increment, 4)
    |> Context.put_var(:current_lights, 11)
    |> GrogVM.put_var(54, -0x50)
    |> GrogVM.put_var(74, 1225)
    |> GrogVM.start_script(1, Keyword.get(opts, :boot_args, []))
  end

  @doc "The jiffies the next frame lasts: variable 19, at least one."
  @spec frame_jiffies(GrogVM.Ctx.t()) :: pos_integer()
  def frame_jiffies(ctx), do: max(Context.var(ctx, :timer_next), 1)

  @doc "Runs one frame lasting `jiffies`, with the player's `inputs` since the last."
  @spec frame(GrogVM.Ctx.t(), pos_integer(), [input()]) :: GrogVM.Ctx.t()
  def frame(ctx, jiffies, inputs) do
    ctx
    |> timers(jiffies)
    |> Talk.tick(jiffies)
    |> pointer(inputs)
    |> screen_vars()
    |> GrogVM.run_frame(jiffies)
    |> handle_inputs(inputs)
    |> run_sentence()
    |> Context.update(&Walking.step_all/1)
    |> Camera.move()
    |> Context.update(&animate/1)
    |> Context.update(&Palette.cycle(&1, jiffies))
    |> Context.update(&Sounds.tick(&1, jiffies))
    |> Context.update(&Shake.tick(&1, jiffies))
  end

  defp timers(ctx, jiffies) do
    ctx
    |> add_var(:timer_1, jiffies)
    |> add_var(:timer_2, jiffies)
    |> add_var(:timer_3, jiffies)
    |> add_var(:timer_total, jiffies)
    |> Context.put_var(:timer, jiffies)
    |> music_timer(jiffies)
  end

  defp music_timer(ctx, jiffies) do
    playing = Enum.any?(Context.world(ctx).sounds, fn {_number, entry} -> entry.music end)
    if playing, do: add_var(ctx, :music_timer, jiffies), else: ctx
  end

  defp add_var(ctx, name, amount), do: Context.put_var(ctx, name, Context.var(ctx, name) + amount)

  defp pointer(ctx, inputs) do
    case inputs |> Enum.flat_map(&point_of/1) |> List.last() do
      nil -> ctx
      latest -> Context.update(ctx, &%{&1 | mouse: latest})
    end
  end

  defp point_of({:click, point, _button}), do: [point]
  defp point_of({:pointer, point}), do: [point]
  defp point_of({:key, _key}), do: []

  defp screen_vars(ctx) do
    world = Context.world(ctx)
    {x, y} = world.mouse

    ctx
    |> Context.put_var(:mouse_x, x)
    |> Context.put_var(:mouse_y, y)
    |> Context.put_var(:virtual_mouse_x, x + Camera.left(world))
    |> Context.put_var(:virtual_mouse_y, y - world.screen.top)
    |> Context.put_var(:camera_pos_x, world.camera.x)
    |> Context.put_var(:have_msg, if(world.message, do: 0xFF, else: 0))
  end

  defp handle_inputs(ctx, inputs), do: Enum.reduce(inputs, ctx, &handle_input/2)

  defp handle_input({:pointer, _point}, ctx), do: ctx

  defp handle_input({:key, key}, ctx) do
    cond do
      key == Context.var(ctx, :cutscene_exit_key) -> GrogVM.abort_cutscene(ctx)
      key == Context.var(ctx, :talk_stop_key) -> Talk.skip(ctx)
      accepts_input?(ctx) -> key_input(ctx, key)
      true -> ctx
    end
  end

  defp handle_input({:click, point, button}, ctx) do
    if accepts_input?(ctx), do: click_input(ctx, point, button_code(button)), else: ctx
  end

  defp accepts_input?(ctx), do: Context.world(ctx).cursor.userput > 0

  defp key_input(ctx, key) do
    case Verbs.with_key(Context.world(ctx), key) do
      nil -> verb_script(ctx, [4, key, 1])
      verb -> verb_script(ctx, [1, verb.id, 1])
    end
  end

  defp click_input(ctx, {_x, y} = point, code) do
    world = Context.world(ctx)

    case Verbs.at(world, point) do
      nil ->
        verb_script(ctx, [if(y < world.screen.top + world.screen.height, do: 2, else: 1), 0, code])

      verb ->
        verb_script(ctx, [1, verb.id, code])
    end
  end

  defp button_code(:left), do: 1
  defp button_code(:right), do: 2

  defp verb_script(ctx, args) do
    case Context.var(ctx, :verb_script) do
      0 -> ctx
      script -> GrogVM.start_script(ctx, script, args)
    end
  end

  defp run_sentence(ctx) do
    world = Context.world(ctx)
    script = Context.var(ctx, :sentence_script)

    cond do
      world.sentences == [] -> ctx
      GrogVM.sentences_frozen?(ctx) -> ctx
      sentence_busy?(ctx, script) -> ctx
      true -> start_sentence(ctx, script, List.last(world.sentences))
    end
  end

  defp sentence_busy?(ctx, script) do
    ctx
    |> GrogVM.scripts()
    |> Enum.any?(&(&1.number == script and &1.kind in [:global, :local] and &1.frozen == 0))
  end

  defp start_sentence(ctx, script, {verb, object_a, object_b}) do
    ctx =
      Context.update(
        ctx,
        &%{&1 | sentences: List.delete_at(&1.sentences, length(&1.sentences) - 1)}
      )

    cond do
      object_b != 0 and object_a == object_b -> ctx
      script == 0 -> ctx
      true -> GrogVM.start_script(ctx, script, [verb, object_a, object_b])
    end
  end

  defp animate(world) do
    world
    |> World.actors_in_room()
    |> Enum.filter(& &1.visible)
    |> Enum.reduce(world, fn actor, acc ->
      World.update_actor(acc, actor.number, &Actor.step_animation/1)
    end)
  end
end
