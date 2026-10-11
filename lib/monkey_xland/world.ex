defmodule MonkeyXland.World do
  @moduledoc """
  Everything the game's scripts change that is not a script variable: the room on
  screen, every object's owner, state and classes, the inventory, the actors, the verbs,
  the strings, the camera, the palette, the cursor, the text being shown, the queued
  sentences and the sounds playing.

  A world is the host state of a `GrogVM.Ctx`; `MonkeyXland.Host` changes it as scripts
  run, and `MonkeyXland.Engine` advances it each frame.

  * `objects` — every object's `%{owner: 0..15, state: 0..15, classes: integer}`;
    owner 15 means the object belongs to its room,
  * `room_objects` — the current room's objects (`MonkeyXland.Scumm.Room.Object`), in
    file order, with any carried in by `load_object`,
  * `positions` — objects moved by `draw_object … at`,
  * `inventory` — objects picked up, in the order they were,
  * `strings` — string resources by number, as bytes,
  * `text` — the slots `print` writes: 0 for actors talking, 1 to 3 for the others,
  * `message` — the message being shown (`MonkeyXland.Message`) or `nil`,
  * `events` — what clients must hear or see since they last asked: sounds started and
    stopped, music, voices, quitting,
  * `lights` — the lighting `lights` last set (variable 9); with bit 2 clear the room is
    dark and is not drawn,
  * `screen` — the rows the room is drawn in (`top`, `height`) and the screen shaking
    (`shake`, a `MonkeyXland.Shake` state),
  * `boxes` — the walk boxes as scripts changed them in this room: `flags` and `scales`
    by box, `routes` (`nil` until a script rebuilds them), `scale_slots`, and `drawn`,
    the rectangles `draw_box` drew,
  * `effect` — the room transition a script chose (`kind`), and whether a room was
    entered since (`pending`).
  """

  alias MonkeyXland.{Actor, Assets, Shake}
  alias MonkeyXland.Scumm.Room

  @actors 1..13
  @screen_width 320
  @boxes %{flags: %{}, scales: %{}, routes: nil, scale_slots: %{}, drawn: []}

  @enforce_keys [:objects]
  defstruct [
    :objects,
    room: 0,
    room_resource: 0,
    room_data: nil,
    room_objects: [],
    positions: %{},
    object_names: %{},
    inventory: [],
    actors: %{},
    verbs: %{},
    strings: %{},
    text: %{},
    message: nil,
    camera: %{x: 160, dest: 160, mode: :normal, follows: 0, moving_to_actor: false},
    screen: %{top: 0, height: 144, shake: Shake.still()},
    palette: <<>>,
    base_palette: <<>>,
    cycles: [],
    cursor: %{state: 0, userput: 0, shape: 0, hotspot: {0, 0}},
    charset: 0,
    charset_colors: %{},
    sentences: [],
    boxes: @boxes,
    pseudo_rooms: %{},
    sounds: %{},
    events: [],
    mouse: {0, 0},
    effect: %{kind: 0, pending: false},
    ego_positioned: false,
    saved_text: %{},
    lights: 11
  ]

  @type object_entry :: %{owner: 0..15, state: 0..15, classes: non_neg_integer()}
  @type t :: %__MODULE__{}

  @doc "The walk-box state of a room just entered: nothing set by a script, nothing drawn."
  @spec room_boxes() :: map()
  def room_boxes, do: @boxes

  @doc "The world at power-on: no room, every object as the index has it, every actor at its defaults."
  @spec new() :: t()
  def new do
    objects = Assets.get().install.index.objects
    actors = Map.new(@actors, &{&1, Actor.new(&1)})
    text = Map.new(0..5, &{&1, default_text()})
    black = :binary.copy(<<0>>, 768)
    %__MODULE__{objects: objects, actors: actors, text: text, palette: black, base_palette: black}
  end

  @doc "The settings a text slot starts with."
  @spec default_text() :: map()
  def default_text,
    do: %{
      x: 2,
      y: 5,
      right: @screen_width - 1,
      color: 15,
      center: false,
      overhead: false,
      charset: 0
    }

  @doc "The actor numbered `number`, or `nil` for a number no actor has."
  @spec actor(t(), integer()) :: Actor.t() | nil
  def actor(%__MODULE__{actors: actors}, number), do: Map.get(actors, number)

  @doc "Changes actor `number` with `fun`; a number no actor has changes nothing."
  @spec update_actor(t(), integer(), (Actor.t() -> Actor.t())) :: t()
  def update_actor(%__MODULE__{actors: actors} = world, number, fun)
      when is_map_key(actors, number),
      do: %{world | actors: Map.update!(actors, number, fun)}

  def update_actor(world, _number, _fun), do: world

  @doc "Whether `number` is an actor's number rather than an object's."
  @spec actor?(t(), integer()) :: boolean()
  def actor?(%__MODULE__{actors: actors}, number), do: is_map_key(actors, number)

  @doc "The actors standing in the current room."
  @spec actors_in_room(t()) :: [Actor.t()]
  def actors_in_room(%__MODULE__{actors: actors, room: room}),
    do: for({_number, actor} <- Enum.sort(actors), actor.room == room and room != 0, do: actor)

  @doc "An object's entry, every field 0 for an object the index lacks."
  @spec object(t(), non_neg_integer()) :: object_entry()
  def object(%__MODULE__{objects: objects}, number),
    do: Map.get(objects, number, %{owner: 0, state: 0, classes: 0})

  @doc "Changes object `number`'s entry with `fun`."
  @spec update_object(t(), non_neg_integer(), (object_entry() -> object_entry())) :: t()
  def update_object(%__MODULE__{objects: objects} = world, number, fun),
    do: %{world | objects: Map.put(objects, number, fun.(object(world, number)))}

  @doc "The current room's object numbered `number`, or `nil`."
  @spec room_object(t(), non_neg_integer()) :: Room.Object.t() | nil
  def room_object(%__MODULE__{room_objects: objects}, number),
    do: Enum.find(objects, &(&1.number == number))

  @doc "Adds an event for clients."
  @spec emit(t(), term()) :: t()
  def emit(%__MODULE__{events: events} = world, event), do: %{world | events: [event | events]}

  @doc "The events since the last call, oldest first, and the world without them."
  @spec take_events(t()) :: {[term()], t()}
  def take_events(%__MODULE__{events: events} = world),
    do: {Enum.reverse(events), %{world | events: []}}

  @doc "The screen's width in pixels."
  @spec screen_width() :: pos_integer()
  def screen_width, do: @screen_width
end
