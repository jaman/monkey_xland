defmodule MonkeyXland.Client do
  @moduledoc """
  The Secret of Monkey Island as a `Cauldron2D.Client.Game`: the game's screen filling
  the pane at 4:3, the pointer, the keys, and the sound.

      mix monkey_xland --game "path/to/The Secret of Monkey Island Special Edition"

  The left mouse button does what the verb chosen says (walking, at first); the right
  button does what the thing under the pointer suggests. Keys: the verbs' own letters,
  `.` skips the text on screen, Escape skips a cutscene, F10 opens the menu: resume, save,
  load, restart, quit.
  """

  @behaviour Cauldron2D.Client.Game

  alias MonkeyXland.{Audio, Game, Keys, Menu, Music, Screen}

  @atlas :monkey_xland

  @impl true
  def title,
    do: %{name: "MonkeyXland", tagline: "The Secret of Monkey Island, from your own copy"}

  @impl true
  def atlas do
    unless Cauldron2D.Atlas.installed?(@atlas) do
      @atlas |> Cauldron2D.Atlas.new(tile: 16, void: {0, 0, 0}) |> Cauldron2D.Atlas.install()
    end

    @atlas
  end

  @impl true
  def actions, do: [:click, :alt_click] ++ Keys.actions()

  @impl true
  def keymaps do
    keys = Keys.keymap()
    mouse = %{click: [{:mouse, :left}], alt_click: [{:mouse, :right}]}
    [mouse: Map.merge(keys, mouse)]
  end

  @impl true
  def toggles, do: []

  @impl true
  def client_keys do
    %{
      menu: :f10,
      back: nil,
      settings: nil,
      settings_menu: nil,
      title: nil,
      talk: nil,
      watch: nil,
      team: nil,
      chat: nil,
      guide: nil,
      projection: nil,
      turn_left: nil,
      turn_right: nil,
      tilt_up: nil,
      tilt_down: nil,
      zoom_in: nil,
      zoom_out: nil,
      zoom_reset: nil
    }
  end

  @impl true
  def start, do: {:play, :monkey}

  @impl true
  def look,
    do: %{
      projection: :picture,
      projections: [:picture],
      automap: false,
      native: {320, 200},
      picture: [{:native, 2}, :swap]
    }

  @impl true
  def chat?, do: false

  @impl true
  def lobby?, do: false

  @impl true
  def worlds(_props) do
    [
      %{
        id: :monkey,
        name: "The Secret of Monkey Island",
        world: {Game, [hz: 60, game_opts: []]},
        players: 0,
        humans: []
      }
    ]
  end

  @impl true
  def scene(view), do: scene(view, look())

  @impl true
  def open_menu(settings), do: Menu.open(settings)

  @impl true
  def menu_event(menu, event, settings), do: Menu.event(menu, event, settings)

  @impl true
  def scene(view, look) do
    %{
      focus: {0.0, 0.0},
      bounds: :unbounded,
      cell: fn _cell -> nil end,
      movers: [],
      frame: Screen.frame(),
      picture: fn size, aspect ->
        Screen.raster(Map.get(view, :screen), size, aspect, Map.get(look, :menu))
      end
    }
  end

  @impl true
  def hud(_view), do: []

  @impl true
  def listener(_view), do: nil

  @impl true
  def sounds, do: &Audio.voice/1

  @impl true
  def music, do: [{Music.piece(), Music.spec()}]

  @impl true
  def cue(view, _screen),
    do: %{
      piece: Music.piece(),
      section: Music.section(Map.get(view, :cd_track)),
      layers: %{cd: 1.0}
    }

  @impl true
  def outcome(%{quit: true}),
    do: %{title: "THE SECRET OF MONKEY ISLAND", lines: ["Thanks for playing."], next: :lobby}

  def outcome(_view), do: nil
end
