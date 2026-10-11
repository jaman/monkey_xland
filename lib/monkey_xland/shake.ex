defmodule MonkeyXland.Shake do
  @moduledoc """
  The screen shaking: while a script has it on, the whole screen is shown shifted up by
  0, 1, 2, 1, 0, 2, 3 and 1 pixels in turn, moving on every 8 ticks of the 291.304 Hz
  sound timer.

  The state lives in the world's `screen.shake` as `%{on: boolean, frame: 0..7,
  clock: jiffies}`; `tick/2` advances it each frame and `offset/1` is the shift to draw
  with.
  """

  alias MonkeyXland.World

  @positions {0, 1, 2, 1, 0, 2, 3, 1}
  @timer_hz 291.304
  @ticks_per_step 8
  @jiffies_per_second 60
  @period @ticks_per_step * @jiffies_per_second / @timer_hz

  @type t :: %{on: boolean(), frame: 0..7, clock: number()}

  @doc "The shake at rest, as a world starts and as a script turns it on or off."
  @spec still() :: t()
  def still, do: %{on: false, frame: 0, clock: 0}

  @doc "Starts the screen shaking from its first position."
  @spec on(World.t()) :: World.t()
  def on(%{} = world), do: put(world, %{still() | on: true})

  @doc "Stops the screen shaking and shows it in place."
  @spec off(World.t()) :: World.t()
  def off(%{} = world), do: put(world, still())

  @doc "Advances the shake by a frame lasting `jiffies`; a still screen stays still."
  @spec tick(World.t(), pos_integer()) :: World.t()
  def tick(%{screen: %{shake: %{on: false}}} = world, _jiffies), do: world

  def tick(%{screen: %{shake: shake}} = world, jiffies),
    do: put(world, advance(%{shake | clock: shake.clock + jiffies}))

  @doc "How many pixels up the screen is shown this frame."
  @spec offset(World.t()) :: 0..3
  def offset(%{screen: %{shake: %{on: false}}}), do: 0
  def offset(%{screen: %{shake: %{frame: frame}}}), do: elem(@positions, frame)

  defp advance(%{clock: clock} = shake) when clock < @period, do: shake

  defp advance(%{clock: clock, frame: frame} = shake),
    do: advance(%{shake | clock: clock - @period, frame: rem(frame + 1, tuple_size(@positions))})

  defp put(%{screen: screen} = world, shake), do: %{world | screen: %{screen | shake: shake}}
end
