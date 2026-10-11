defmodule MonkeyXland.Menu do
  @moduledoc """
  The menu the client's menu key opens over the game: resume, save, load, restart and
  quit, and for save and load the nine slots with the room each holds.

      menu = MonkeyXland.Menu.open(settings)
      %{menu: menu, settings: settings} = MonkeyXland.Menu.event(menu, {:key, :down}, settings)

  `↑`/`↓` move, `Enter` chooses, `Escape` goes back (or closes). Saving, loading and
  restarting go to the world as the requests `{:save, slot}`, `{:load, slot}` and
  `:restart`; quitting leaves the world.
  """

  alias MonkeyXland.{Assets, Save}

  defstruct page: :main, cursor: 0, saves: []

  @type t :: %__MODULE__{
          page: :main | :save | :load,
          cursor: non_neg_integer(),
          saves: [Save.summary()]
        }

  @main [:resume, :save, :load, :restart, :quit]
  @titles %{resume: "Resume", save: "Save", load: "Load", restart: "Restart", quit: "Quit"}

  @doc "The menu as it opens."
  @spec open(map()) :: t()
  def open(_settings), do: %__MODULE__{saves: Save.list()}

  @doc "One key or button event while the menu is open; see `Cauldron2D.Client.Game.menu_event/3`."
  @spec event(t(), term(), map()) :: map()
  def event(menu, {:key, :up}, settings), do: %{menu: move(menu, -1), settings: settings}
  def event(menu, {:key, :down}, settings), do: %{menu: move(menu, 1), settings: settings}

  def event(%__MODULE__{page: :main}, {:key, :escape}, settings),
    do: %{menu: nil, settings: settings}

  def event(menu, {:key, :escape}, settings),
    do: %{menu: %{menu | page: :main, cursor: 0}, settings: settings}

  def event(menu, {:key, :enter}, settings), do: choose(menu, settings)
  def event(menu, _event, settings), do: %{menu: menu, settings: settings}

  @doc "The menu's title and its lines, the line under the cursor marked `true`."
  @spec lines(t()) :: {String.t(), [{String.t(), boolean()}]}
  def lines(%__MODULE__{page: :main, cursor: cursor}) do
    {"MonkeyXland",
     @main
     |> Enum.with_index()
     |> Enum.map(fn {item, index} -> {@titles[item], index == cursor} end)}
  end

  def lines(%__MODULE__{page: page, cursor: cursor, saves: saves}) do
    lines = Enum.map(Save.slots(), fn slot -> {slot_line(slot, saves), slot - 1 == cursor} end)
    {if(page == :save, do: "Save in which slot?", else: "Load which game?"), lines}
  end

  defp slot_line(slot, saves) do
    case Enum.find(saves, &(&1.slot == slot)) do
      nil ->
        "#{slot}. (empty)"

      save ->
        "#{slot}. #{room_name(save.room)}, #{Calendar.strftime(save.saved_at, "%Y-%m-%d %H:%M")}"
    end
  end

  defp room_name(room), do: Map.get(Assets.get().install.index.room_names, room, "room #{room}")

  defp move(%__MODULE__{page: :main, cursor: cursor} = menu, step),
    do: %{menu | cursor: Integer.mod(cursor + step, length(@main))}

  defp move(%__MODULE__{cursor: cursor} = menu, step),
    do: %{menu | cursor: Integer.mod(cursor + step, Enum.count(Save.slots()))}

  defp choose(%__MODULE__{page: :main, cursor: cursor} = menu, settings),
    do: main(Enum.at(@main, cursor), menu, settings)

  defp choose(%__MODULE__{page: :save, cursor: cursor}, settings),
    do: %{menu: nil, settings: settings, request: {:save, cursor + 1}}

  defp choose(%__MODULE__{page: :load, cursor: cursor, saves: saves} = menu, settings) do
    if Enum.any?(saves, &(&1.slot == cursor + 1)),
      do: %{menu: nil, settings: settings, request: {:load, cursor + 1}},
      else: %{menu: menu, settings: settings}
  end

  defp main(:resume, _menu, settings), do: %{menu: nil, settings: settings}

  defp main(:save, menu, settings),
    do: %{menu: %{menu | page: :save, cursor: 0}, settings: settings}

  defp main(:load, menu, settings),
    do: %{menu: %{menu | page: :load, cursor: 0}, settings: settings}

  defp main(:restart, _menu, settings), do: %{menu: nil, settings: settings, request: :restart}
  defp main(:quit, _menu, settings), do: %{menu: nil, settings: settings, leave: true}
end
