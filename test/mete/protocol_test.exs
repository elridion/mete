defmodule Mete.ProtocolTest do
  use ExUnit.Case

  import Mete.Protocol
  import IO, only: [iodata_to_binary: 1]

  def escape(string) do
    string
    |> escape_string()
    |> iodata_to_binary()
  end

  describe "string escape" do
    test "no escapes" do
      assert "abc" == escape("abc")
    end

    test "escape comma" do
      assert ~S"\," == escape(",")
      assert ~S"abc\," == escape("abc,")
      assert ~S"abc\,there" == escape("abc,there")
      assert ~S"abc\,there\,were" == escape("abc,there,were")
    end

    test "escape space" do
      assert ~S"\ " == escape(" ")
      assert ~S"abc\ " == escape("abc ")
      assert ~S"abc\ there" == escape("abc there")
      assert ~S"abc\ there\ were" == escape("abc there were")
    end

    test "escape equal sign" do
      assert ~S"\=" == escape("=")
      assert ~S"abc\=" == escape("abc=")
      assert ~S"abc\=there" == escape("abc=there")
      assert ~S"abc\=there\=were" == escape("abc=there=were")
    end

    # test "escape slashes" do
    #   assert "\\\\" == escape("\\")
    #   assert "abc\\\\" == escape("abc\\")
    #   assert "abc\\\\there" == escape("abc\\there")
    #   assert "abc\\\\there\\\\were" == escape("abc\\there\\were")
    # end

    test "mixed escapes" do
      # assert ~S"\,\ \=\\" == escape(", =\\")
      assert "\\,\\ \\=\\" == escape(", =\\")

      assert ~S"This\ sentence\,\ uses\=all\\,of\ theEscape!signs" ==
               escape("This sentence, uses=all\\,of theEscape!signs")
    end
  end

  describe "encode tags" do
    test "encode" do
      assert "" == iodata_to_binary(encode_tags([]))
      assert ",region=eu" == iodata_to_binary(encode_tags([{"region", "eu"}]))

      assert ",region=eu,server=prod" ==
               iodata_to_binary(encode_tags([{"region", "eu"}, {"server", "prod"}]))
    end
  end

  describe "encode fields" do
    test "encode value" do
      assert "1i" == iodata_to_binary(encode_field_value(1))
      assert "1.0" == iodata_to_binary(encode_field_value(1.0))
      assert "t" == iodata_to_binary(encode_field_value(true))
      assert "f" == iodata_to_binary(encode_field_value(false))
      assert "\"error\"" == iodata_to_binary(encode_field_value("error"))
    end

    test "encode field" do
      assert "value=1i" == iodata_to_binary(encode_field({"value", 1}))
      assert "value=1.0" == iodata_to_binary(encode_field({"value", 1.0}))
      assert "value=t" == iodata_to_binary(encode_field({"value", true}))
      assert "value=f" == iodata_to_binary(encode_field({"value", false}))
      assert "value=\"error\"" == iodata_to_binary(encode_field({"value", "error"}))
    end

    test "encode fields" do
      assert_raise FunctionClauseError, fn ->
        encode_fields([])
      end

      assert "value=1i" == iodata_to_binary(encode_fields([{"value", 1}]))

      assert "value=1i,value=1.0" ==
               iodata_to_binary(encode_fields([{"value", 1}, {"value", 1.0}]))
    end
  end

  describe "encode points" do
    assert "query exec=12.0,queue=33i -5479885" ==
             iodata_to_binary(encode("query", [], [{"exec", 12.0}, {"queue", 33}], -5_479_885))

    assert "query,country=us,region=west exec=12.0,queue=33i -5479885" ==
             iodata_to_binary(
               encode(
                 "query",
                 [{"country", "us"}, {"region", "west"}],
                 [{"exec", 12.0}, {"queue", 33}],
                 -5_479_885
               )
             )
  end
end
