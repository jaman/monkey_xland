defmodule MonkeyXland.Talk do
  @moduledoc """
  Actors talking and the narrator printing.

  `say/5` replaces whatever was being said (unless the text asks to keep it), sets the
  talking actor (variable 25, `0xFF` for none), starts the actor's talk animation when it
  stands in the room, and shows the message's first page. `tick/2` counts a page's time
  down and turns to the next page, or ends the message: the talk-stop animation runs and
  `have_msg` (variable 3) drops to 0.
  """

  alias MonkeyXland.{Actor, Context, Message, World}

  @no_actor 0xFF

  @doc "Says `parts` (a read message) as `actor` with text-slot `settings`, each page with its voice."
  @spec say(GrogVM.Ctx.t(), non_neg_integer(), map(), [term()], [MonkeyXland.Voices.voice() | nil]) ::
          GrogVM.Ctx.t()
  def say(ctx, actor, settings, parts, voices \\ []) do
    ctx = if :keep in parts, do: ctx, else: stop(ctx)
    world = Context.world(ctx)
    speaker = if World.actor?(world, actor), do: actor, else: @no_actor

    ctx
    |> Context.put_var(:talk_actor, speaker)
    |> Context.update(&start_talking(&1, speaker))
    |> then(fn ctx ->
      Context.update(
        ctx,
        &%{&1 | message: Message.new(&1, Context.text_env(ctx), speaker, settings, parts, voices)}
      )
    end)
    |> Context.update(&speak/1)
    |> Context.put_var(:have_msg, 0xFF)
  end

  @doc "Ends the message being shown, if any."
  @spec stop(GrogVM.Ctx.t()) :: GrogVM.Ctx.t()
  def stop(ctx) do
    case Context.world(ctx).message do
      nil ->
        ctx

      %Message{actor: actor} = message ->
        ctx
        |> Context.update(&stop_talking(&1, actor))
        |> Context.update(&silence(&1, message))
        |> Context.update(&%{&1 | message: nil})
        |> finished()
    end
  end

  @doc "Counts `jiffies` off the page shown; turns the page or ends the message when its time is up."
  @spec tick(GrogVM.Ctx.t(), non_neg_integer()) :: GrogVM.Ctx.t()
  def tick(ctx, jiffies) do
    case Context.world(ctx).message do
      nil ->
        ctx

      %Message{delay: delay} = message when delay - jiffies > 0 ->
        Context.update(ctx, &%{&1 | message: %{message | delay: delay - jiffies}})

      message ->
        next_page(ctx, message)
    end
  end

  @doc "Ends the page shown now, as when the player skips it."
  @spec skip(GrogVM.Ctx.t()) :: GrogVM.Ctx.t()
  def skip(ctx) do
    case Context.world(ctx).message do
      nil -> ctx
      message -> next_page(ctx, message)
    end
  end

  defp next_page(ctx, message) do
    if Message.more?(message),
      do:
        ctx
        |> Context.update(
          &%{
            &1
            | message: Message.show_page(message, &1, Context.text_env(ctx), message.page + 1)
          }
        )
        |> Context.update(&speak/1),
      else: stop(ctx)
  end

  defp speak(%World{message: message} = world) do
    case Message.voice(message) do
      nil -> world
      %{index: index} -> World.emit(world, {:play_voice, index})
    end
  end

  defp silence(world, message) do
    case Message.voice(message) do
      nil -> world
      _voice -> World.emit(world, :stop_voice)
    end
  end

  defp finished(ctx),
    do: ctx |> Context.put_var(:have_msg, 0) |> Context.put_var(:talk_actor, @no_actor)

  defp start_talking(world, @no_actor), do: world

  defp start_talking(world, actor),
    do: World.update_actor(world, actor, &talk_frame(&1, world, :talk_start))

  defp stop_talking(world, @no_actor), do: world

  defp stop_talking(world, actor),
    do: World.update_actor(world, actor, &talk_frame(&1, world, :talk_stop))

  defp talk_frame(%Actor{room: room} = actor, %World{room: room}, which) when room != 0,
    do: Actor.start_frame(actor, Map.fetch!(actor.frames, which))

  defp talk_frame(actor, _world, _which), do: actor
end
