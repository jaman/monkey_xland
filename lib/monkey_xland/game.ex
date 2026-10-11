defmodule MonkeyXland.Game do
  @moduledoc """
  The Secret of Monkey Island as a `Cauldron2D.Game`, run at 60 ticks a second — one
  SCUMM jiffy a tick. A SCUMM frame plays each time the jiffies its scripts asked for
  (variable 19) have passed; its screen is drawn then.

      Cauldron2D.World.start_link(game: MonkeyXland.Game, hz: 60)

  The owner's game must have been loaded with `MonkeyXland.Assets.load/1`.

  Input: `aim` is the pointer as fractions of the screen (see `Cauldron2D.Fit`); the
  action `:click` held anew clicks the left button there, `:alt_click` the right, and a
  key action (`MonkeyXland.Keys`) types that key. The requests `{:save, slot}`,
  `{:load, slot}` and `:restart` (from `MonkeyXland.Menu`) save, load or start over.

  The view is `%{screen: MonkeyXland.Picture.t() | nil, quit: boolean, cd_track: n | nil}`:
  `quit` set once the game asks to end, `cd_track` the CD music playing. Events are the world's sounds as `Cauldron2D.Audio` events
  (`MonkeyXland.Audio.events/1`).
  """

  @behaviour Cauldron2D.Game

  alias MonkeyXland.{Engine, Keys, Picture, World}

  @jiffy 1 / 60
  @screen {320, 200}

  @impl true
  def init(opts) do
    %{
      ctx: Engine.new(Keyword.take(opts, [:seed, :boot_args])),
      jiffies: 0.0,
      inputs: [],
      held: MapSet.new(),
      screen: nil,
      events: [],
      quit: false,
      request: 0
    }
  end

  @impl true
  def join(state, _id, _props), do: {:ok, state}

  @impl true
  def leave(state, _id), do: state

  @impl true
  def handle_input(state, id, %{request: {number, request}} = input)
      when number > state.request do
    state
    |> requested(request)
    |> Map.put(:request, number)
    |> handle_input(id, Map.delete(input, :request))
  end

  def handle_input(state, _id, %{held: held} = input) do
    point = point(Map.get(input, :aim))
    pressed = MapSet.difference(held, state.held)
    inputs = moved(point) ++ Enum.flat_map(pressed, &pressed(&1, point || current_mouse(state)))
    %{state | held: held, inputs: state.inputs ++ inputs}
  end

  @impl true
  def step(state, dt), do: play(%{state | jiffies: state.jiffies + dt / @jiffy})

  @impl true
  def view(state, _id),
    do: %{
      screen: state.screen,
      quit: state.quit,
      cd_track: MonkeyXland.Sounds.cd_playing(state.ctx.host)
    }

  @impl true
  def drain_events(state), do: {MonkeyXland.Audio.events(state.events), %{state | events: []}}

  defp play(%{ctx: ctx, jiffies: jiffies} = state) do
    frame = Engine.frame_jiffies(ctx)

    if jiffies >= frame do
      ctx = Engine.frame(ctx, frame, state.inputs)
      {events, world} = World.take_events(ctx.host)
      ctx = %{ctx | host: world}
      quit = state.quit or {:system, :quit} in events

      play(%{
        state
        | ctx: ctx,
          jiffies: jiffies - frame,
          inputs: [],
          screen: Picture.draw(world),
          events: state.events ++ events,
          quit: quit
      })
    else
      state
    end
  end

  defp requested(state, {:save, slot}) do
    MonkeyXland.Save.write(state.ctx, slot)
    state
  end

  defp requested(state, {:load, slot}) do
    case MonkeyXland.Save.read(slot) do
      {:ok, ctx} -> %{state | ctx: ctx, jiffies: 0.0, inputs: [], screen: Picture.draw(ctx.host)}
      {:error, _reason} -> state
    end
  end

  defp requested(state, :restart),
    do: %{state | ctx: Engine.new(), jiffies: 0.0, inputs: [], screen: nil}

  defp point(nil), do: nil

  defp point({u, v}),
    do: {min(trunc(u * elem(@screen, 0)), 319), min(trunc(v * elem(@screen, 1)), 199)}

  defp moved(nil), do: []
  defp moved(point), do: [{:pointer, point}]

  defp current_mouse(%{ctx: ctx}), do: ctx.host.mouse

  defp pressed(:click, point), do: [{:click, point, :left}]
  defp pressed(:alt_click, point), do: [{:click, point, :right}]

  defp pressed(action, _point) do
    case Keys.code(action) do
      nil -> []
      code -> [{:key, code}]
    end
  end
end
