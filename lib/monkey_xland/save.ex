defmodule MonkeyXland.Save do
  @moduledoc """
  Saved games: nine slots in the user data directory's `monkey_xland`, each the script
  machine and the world as they stood.

  Each running script's code is saved as what it is — global script `n`, a room's entry
  or exit script, a room's local script `n`, an object's code — and found again in the
  game when loaded, so a save outlives a change to how scripts are compiled. Rooms are
  read back from the game, not from the save.

      {:ok, _path} = MonkeyXland.Save.write(ctx, 1)
      {:ok, ctx} = MonkeyXland.Save.read(1)
      [%{slot: 1, room: 33, saved_at: _}] = MonkeyXland.Save.list()
  """

  alias GrogVM.{Ctx, Machine, Slot}
  alias MonkeyXland.{Assets, Host, World}

  @slots 1..9
  @version 3

  @type summary :: %{slot: pos_integer(), room: non_neg_integer(), saved_at: NaiveDateTime.t()}

  @doc "The slots a game can be saved in."
  @spec slots() :: Range.t()
  def slots, do: @slots

  @doc "Saves `ctx` in `slot`."
  @spec write(Ctx.t(), pos_integer()) :: {:ok, Path.t()} | {:error, term()}
  def write(%Ctx{machine: machine, host: world}, slot) when slot in @slots do
    names = code_names()

    saved = %{
      version: @version,
      saved_at: NaiveDateTime.local_now(),
      room: world.room,
      machine: %{
        machine
        | slots:
            Map.new(machine.slots, fn {index, entry} ->
              {index, %{entry | code: Map.fetch!(names, entry.code)}}
            end)
      },
      world: %{
        world
        | room_data: nil,
          room_objects: Enum.map(world.room_objects, & &1.number),
          events: []
      }
    }

    path = path(slot)

    with :ok <- File.mkdir_p(Path.dirname(path)),
         :ok <- File.write(path, :erlang.term_to_binary(saved, [:compressed])) do
      {:ok, path}
    end
  end

  @doc "The game saved in `slot`, ready to run."
  @spec read(pos_integer()) :: {:ok, Ctx.t()} | {:error, term()}
  def read(slot) when slot in @slots do
    with {:ok, bytes} <- File.read(path(slot)),
         %{version: @version} = saved <- :erlang.binary_to_term(bytes) do
      {:ok, Ctx.new(Host, restore_world(saved.world), restore_machine(saved.machine))}
    else
      {:error, reason} -> {:error, reason}
      _other -> {:error, :unreadable}
    end
  end

  @doc "The slots holding a save, with the room each was saved in and when."
  @spec list() :: [summary()]
  def list do
    for slot <- @slots,
        {:ok, bytes} <- [File.read(path(slot))],
        %{version: @version} = saved <- [:erlang.binary_to_term(bytes)] do
      %{slot: slot, room: saved.room, saved_at: saved.saved_at}
    end
  end

  defp path(slot),
    do: Path.join(to_string(:filename.basedir(:user_data, "monkey_xland")), "slot_#{slot}.sav")

  defp restore_machine(%Machine{} = machine) do
    modules = code_names() |> Map.new(fn {module, name} -> {name, module} end)

    %{
      machine
      | slots:
          Map.new(machine.slots, fn {index, %Slot{} = entry} ->
            {index, %{entry | code: Map.fetch!(modules, entry.code)}}
          end)
    }
  end

  defp restore_world(%World{} = world) do
    assets = Assets.get()
    data = Map.get(assets.rooms, world.room_resource)
    objects = Enum.flat_map(world.room_objects, &home_object(assets, data, &1))
    %{world | room_data: data, room_objects: objects}
  end

  defp home_object(_assets, nil, _number), do: []

  defp home_object(assets, data, number) do
    room = Map.get(assets.object_rooms, number, data.number)
    found = Enum.find(assets.rooms[room].objects, &(&1.number == number))
    if found, do: [found], else: []
  end

  defp code_names do
    assets = Assets.get()
    globals = for {number, module} <- assets.globals, do: {module, {:global, number}}

    rooms =
      for {room, code} <- assets.room_code,
          entry <- [{code.entry, {:entry, room}}, {code.exit, {:exit, room}}],
          {module, name} = entry,
          module != nil,
          do: {module, name}

    locals =
      for {room, code} <- assets.room_code,
          {number, module} <- code.locals,
          do: {module, {:local, room, number}}

    objects =
      for {room, code} <- assets.room_code,
          {object, {module, _verbs}} <- code.objects,
          do: {module, {:object, room, object}}

    Map.new(globals ++ rooms ++ locals ++ objects)
  end
end
