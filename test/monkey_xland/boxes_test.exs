defmodule MonkeyXland.BoxesTest do
  use ExUnit.Case, async: true

  alias MonkeyXland.Boxes
  alias MonkeyXland.Scumm.Room.Box

  defp line(from, to),
    do: %Box{
      upper_left: from,
      upper_right: to,
      lower_right: to,
      lower_left: from,
      mask: 0,
      flags: 0,
      scale: 255
    }

  test "two path segments meeting end to end open onto each other at that point" do
    assert Boxes.gate(line({9, 76}, {21, 76}), line({21, 76}, {23, 84})) == {{21, 76}, {21, 76}}
  end

  test "boxes sharing an edge open along the shared part" do
    left = %Box{
      upper_left: {0, 0},
      upper_right: {10, 0},
      lower_right: {10, 10},
      lower_left: {0, 10},
      mask: 0,
      flags: 0,
      scale: 255
    }

    right = %Box{
      upper_left: {10, 4},
      upper_right: {20, 4},
      lower_right: {20, 20},
      lower_left: {10, 20},
      mask: 0,
      flags: 0,
      scale: 255
    }

    assert Boxes.gate(left, right) == {{10, 4}, {10, 10}}
  end

  test "a line box holds the points along it" do
    assert Boxes.contains?(line({9, 76}, {21, 76}), {15, 76})
    refute Boxes.contains?(line({9, 76}, {21, 76}), {15, 80})
  end
end
