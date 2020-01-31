defmodule Mete.ConnectionTest do
  use ExUnit.Case

  # iex> IO.iodata_length(@point)
  # 34
  @point [
    ["query", [], 32, [["exec", 61, '12.0'], 44, ["queue", 61, ["33", 105]]]],
    32,
    "-5479885"
  ]

  @point2 [
    ["query", [], 55, [["exec", 61, '12.0'], 44, ["queue", 61, ["33", 105]]]],
    32,
    "-5479885"
  ]

  describe "batch testing" do
    import Mete.Connection

    test "deactivated" do
      assert {:transmit, @point, nil} = batch(@point, nil)
    end

    test "empty buffer" do
      {:batch, {@point, 34, 35}} = batch(@point, {[], 0, 35})
      {:transmit, @point, {[], 0, 33}} = batch(@point, {[], 0, 33})
      {:transmit, @point, {[], 0, 34}} = batch(@point, {[], 0, 34})
    end

    test "filled buffer - batch" do
      assert {:batch, {buffer, buffer_size, 100}} = batch(@point2, {@point, 34, 100})

      assert IO.iodata_to_binary([@point2, "\n", @point]) == IO.iodata_to_binary(buffer)
      assert IO.iodata_length(buffer) == buffer_size
    end

    test "filled buffer - transmit" do
      assert {:transmit, @point, {@point2, 34, 50}} = batch(@point2, {@point, 34, 50})

      # assert IO.iodata_to_binary([@point, "\n", @point]) == IO.iodata_to_binary(buffer)
      # assert IO.iodata_length(buffer) == buffer_size
    end

    test "flush buffer" do
      {:batch, {[], 0, 35}} = batch(nil, {[], 0, 35})
      {:transmit, @point, {[], 0, 100}} = batch(nil, {@point, 34, 100})
    end
  end
end
