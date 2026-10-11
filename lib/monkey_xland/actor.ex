defmodule MonkeyXland.Actor do
  @moduledoc """
  A SCUMM v5 actor: where it is, what it wears, how it walks and talks, and the state of
  its costume's animation.

  Facing is in degrees: 0 north (away from the viewer), 90 east, 180 south, 270 west.
  Costume animations are numbered `4 × frame + direction`, direction 0 west, 1 east,
  2 south, 3 north; the named frames (`init`, `walk`, `stand`, `talk_start`,
  `talk_stop`) are the frame numbers scripts set with `actor_ops`.

  `needs_init` is set when the costume changes; the actor's init frame starts the next
  time it is shown.

  `limbs` holds each limb's place in the costume's command list: `{position, start,
  finish, loop?, frame}` with the frame that limb was started with, or `nil` for a limb
  with nothing to show. `stopped` is the set of limbs a `:stop` command halted.
  """

  alias MonkeyXland.Scumm.Costume

  @enforce_keys [:number]
  defstruct [
    :number,
    room: 0,
    x: 0,
    y: 0,
    elevation: 0,
    costume: 0,
    facing: 180,
    visible: false,
    box: 0,
    walk: nil,
    walk_speed: {8, 2},
    frames: %{init: 1, walk: 2, stand: 3, talk_start: 4, talk_stop: 5},
    palette: %{},
    talk_color: 15,
    name: "",
    width: 24,
    scale: {255, 255},
    z_clip: :auto,
    ignore_boxes: false,
    anim_speed: 0,
    anim_progress: 0,
    shadow: 0,
    talk_x: 0,
    talk_y: -80,
    sound: 0,
    frame: 0,
    limbs: %{},
    stopped: MapSet.new(),
    anim_counter: 0,
    needs_init: true
  ]

  @type limb ::
          {non_neg_integer(), non_neg_integer(), non_neg_integer(), boolean(), non_neg_integer()}
  @type t :: %__MODULE__{
          number: non_neg_integer(),
          room: non_neg_integer(),
          x: integer(),
          y: integer(),
          elevation: integer(),
          costume: non_neg_integer(),
          facing: 0..359,
          visible: boolean(),
          box: non_neg_integer(),
          walk: map() | nil,
          walk_speed: {non_neg_integer(), non_neg_integer()},
          frames: %{atom() => non_neg_integer()},
          palette: %{byte() => byte()},
          talk_color: byte(),
          name: binary(),
          width: non_neg_integer(),
          scale: {non_neg_integer(), non_neg_integer()},
          z_clip: :auto | :never | pos_integer(),
          ignore_boxes: boolean(),
          anim_speed: non_neg_integer(),
          anim_progress: non_neg_integer(),
          shadow: non_neg_integer(),
          talk_x: integer(),
          talk_y: integer(),
          sound: non_neg_integer(),
          frame: non_neg_integer(),
          limbs: %{(0..15) => limb() | nil},
          stopped: MapSet.t(0..15),
          anim_counter: non_neg_integer(),
          needs_init: boolean()
        }

  @named_frames %{
    0x38 => :init,
    0x39 => :walk,
    0x3A => :stand,
    0x3B => :talk_start,
    0x3C => :talk_stop
  }

  @doc "An actor with SCUMM v5's defaults."
  @spec new(non_neg_integer()) :: t()
  def new(number), do: %__MODULE__{number: number}

  @doc "Puts an actor back to its defaults, keeping its number and room."
  @spec reset(t()) :: t()
  def reset(%__MODULE__{number: number, room: room, x: x, y: y}),
    do: %{new(number) | room: room, x: x, y: y}

  @doc "The old four-way direction of a facing: 0 west, 1 east, 2 south, 3 north."
  @spec direction(0..359) :: 0..3
  def direction(facing) when facing in 71..109, do: 1
  def direction(facing) when facing in 109..251, do: 2
  def direction(facing) when facing in 251..289, do: 0
  def direction(_facing), do: 3

  @doc "The facing of an old four-way direction."
  @spec facing(0..3) :: 0..359
  def facing(direction), do: elem({270, 90, 180, 0}, direction)

  @doc "Turns to `facing` at once, restarting each limb's frame in the new direction."
  @spec face(t(), integer()) :: t()
  def face(%__MODULE__{limbs: limbs} = actor, facing) do
    actor = %{actor | facing: Integer.mod(facing, 360)}

    Enum.reduce(limbs, actor, fn
      {_limb, nil}, acc -> acc
      {limb, {_position, _start, _finish, _loop, frame}}, acc -> decode(acc, frame, [limb])
    end)
  end

  @doc """
  Starts animation frame `frame` (or a named frame `0x38..0x3C`) in the actor's current
  direction.
  """
  @spec start_frame(t(), non_neg_integer()) :: t()
  def start_frame(%__MODULE__{frames: frames} = actor, frame) do
    frame = named_frame(frames, Map.get(@named_frames, frame), frame)
    actor = if frame == frames.init, do: %{actor | limbs: %{}, stopped: MapSet.new()}, else: actor
    %{decode(actor, frame, :all) | anim_progress: 0, anim_counter: 0, frame: frame}
  end

  defp named_frame(_frames, nil, frame), do: frame
  defp named_frame(frames, name, _frame), do: Map.fetch!(frames, name)

  @doc """
  Runs an `animate_actor` command: `4 × n + direction` with `n` 61 (turn), 62 (face at
  once) or 63 (stop walking); any other number starts that animation frame.
  """
  @spec animate(t(), non_neg_integer()) :: t() | {:stop_walking, t()} | {:turn, t(), 0..359}
  def animate(actor, animation) do
    direction = facing(rem(animation, 4))

    case div(animation, 4) do
      63 -> {:stop_walking, actor}
      62 -> face(actor, direction)
      61 -> {:turn, actor, direction}
      _frame -> start_frame(actor, animation)
    end
  end

  @doc "Counts one frame toward the next animation step, and steps every limb once the count reaches the animation speed."
  @spec step_animation(t()) :: t()
  def step_animation(%__MODULE__{anim_progress: progress, anim_speed: speed} = actor)
      when progress + 1 < speed,
      do: %{actor | anim_progress: progress + 1}

  def step_animation(%__MODULE__{costume: costume} = actor) do
    case MonkeyXland.Assets.costume(costume) do
      nil -> %{actor | anim_progress: 0}
      loaded -> %{advance_limbs(actor, loaded) | anim_progress: 0}
    end
  end

  @doc "The picture each limb shows now, in drawing order: `[{limb, frame_number}]`."
  @spec showing(t(), Costume.t()) :: [{0..15, non_neg_integer()}]
  def showing(%__MODULE__{limbs: limbs}, %Costume{commands: commands}) do
    commands = List.to_tuple(commands)

    for limb <- 0..15,
        {position, _start, _finish, _loop, _frame} <- [Map.get(limbs, limb)],
        position < tuple_size(commands),
        {:frame, frame} <- [elem(commands, position)],
        do: {limb, frame}
  end

  defp decode(%__MODULE__{costume: costume} = actor, frame, only) do
    case MonkeyXland.Assets.costume(costume) do
      nil -> actor
      loaded -> apply_animation(actor, loaded, frame, only)
    end
  end

  defp apply_animation(actor, %Costume{animations: animations, commands: commands}, frame, only) do
    animations
    |> Map.get(frame * 4 + direction(actor.facing), %{})
    |> Enum.filter(fn {limb, _play} -> only == :all or limb in only end)
    |> Enum.reduce(actor, &apply_limb(&1, &2, List.to_tuple(commands), frame))
  end

  defp apply_limb({limb, :disable}, actor, _commands, _frame),
    do: %{actor | limbs: Map.put(actor.limbs, limb, nil)}

  defp apply_limb({limb, {:play, first, last, loop?}}, actor, commands, frame) do
    case command_at(commands, first) do
      :start -> %{actor | stopped: MapSet.delete(actor.stopped, limb)}
      :stop -> %{actor | stopped: MapSet.put(actor.stopped, limb)}
      _other -> %{actor | limbs: Map.put(actor.limbs, limb, {first, first, last, loop?, frame})}
    end
  end

  defp command_at(commands, position) when position < tuple_size(commands),
    do: elem(commands, position)

  defp command_at(_commands, _position), do: nil

  defp advance_limbs(actor, %Costume{commands: commands}) do
    commands = List.to_tuple(commands)

    Enum.reduce(actor.limbs, actor, fn
      {_limb, nil}, acc ->
        acc

      {limb, state}, acc ->
        if MapSet.member?(acc.stopped, limb),
          do: acc,
          else: advance_limb(acc, limb, state, commands)
    end)
  end

  defp advance_limb(actor, limb, {position, start, finish, loop?, frame}, commands) do
    {next, counted} = next_position(position, start, finish, loop?, commands, 0)

    %{
      actor
      | limbs: Map.put(actor.limbs, limb, {next, start, finish, loop?, frame}),
        anim_counter: actor.anim_counter + counted
    }
  end

  defp next_position(position, start, finish, loop?, commands, counted) do
    next = following(position, start, finish, loop?)

    case command_at(commands, next) do
      :count when start != finish ->
        next_position(next, start, finish, loop?, commands, counted + 1)

      :count ->
        {next, counted + 1}

      :sound when start != finish ->
        next_position(next, start, finish, loop?, commands, counted)

      _shown ->
        {next, counted}
    end
  end

  defp following(position, start, finish, true) when position >= finish, do: start
  defp following(position, _start, _finish, true), do: position + 1
  defp following(position, _start, finish, false) when position == finish, do: position
  defp following(position, _start, _finish, false), do: position + 1
end
