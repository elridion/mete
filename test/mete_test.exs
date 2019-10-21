defmodule MeteTest do
  use ExUnit.Case
  doctest Mete, import: true

  import Mete

  test "measure points" do
    meter(:one)
    Process.sleep(2)
    meter(:two)
    write_meter("points")
  end
end
