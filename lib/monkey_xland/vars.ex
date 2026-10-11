defmodule MonkeyXland.Vars do
  @moduledoc """
  The SCUMM v5 global variables the engine itself reads or writes, by name.

      MonkeyXland.Vars.number(:ego)
      #=> 1
  """

  @numbers %{
    ego: 1,
    camera_pos_x: 2,
    have_msg: 3,
    room: 4,
    override: 5,
    machine_speed: 6,
    me: 7,
    num_actor: 8,
    current_lights: 9,
    current_drive: 10,
    timer_1: 11,
    timer_2: 12,
    timer_3: 13,
    music_timer: 14,
    actor_range_min: 15,
    actor_range_max: 16,
    camera_min_x: 17,
    camera_max_x: 18,
    timer_next: 19,
    virtual_mouse_x: 20,
    virtual_mouse_y: 21,
    room_resource: 22,
    last_sound: 23,
    cutscene_exit_key: 24,
    talk_actor: 25,
    camera_fast_x: 26,
    scroll_script: 27,
    entry_script: 28,
    entry_script_2: 29,
    exit_script: 30,
    exit_script_2: 31,
    verb_script: 32,
    sentence_script: 33,
    inventory_script: 34,
    cutscene_start_script: 35,
    cutscene_end_script: 36,
    char_increment: 37,
    walk_to_object: 38,
    debug_mode: 39,
    heap_space: 40,
    restart_key: 42,
    pause_key: 43,
    mouse_x: 44,
    mouse_y: 45,
    timer: 46,
    timer_total: 47,
    sound_card: 48,
    video_mode: 49,
    main_menu_key: 50,
    fixed_disk: 51,
    cursor_state: 52,
    userput: 53,
    sound_result: 56,
    talk_stop_key: 57,
    fade_delay: 59,
    no_subtitles: 60,
    sound_param: 64,
    sound_param_2: 65,
    sound_param_3: 66,
    input_mode: 67,
    memory_performance: 68,
    video_performance: 69,
    room_flag: 70,
    game_loaded: 71,
    new_room: 72
  }

  @doc "The variable number of a named engine variable."
  @spec number(atom()) :: non_neg_integer()
  def number(name), do: Map.fetch!(@numbers, name)

  @doc "The machine settings GrogVM needs: the override and cutscene script variables."
  @spec machine_config() :: GrogVM.Machine.config()
  def machine_config,
    do: %{
      override: number(:override),
      cutscene_start_script: number(:cutscene_start_script),
      cutscene_end_script: number(:cutscene_end_script)
    }
end
