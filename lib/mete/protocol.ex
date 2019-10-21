defmodule Mete.Protocol do
  @moduledoc false
  @type measurement :: String.t() | atom()

  @type tag :: {atom(), String.t()}
  # @type tag :: {String.t() | atom(), String.t()}
  # @type tag_set :: list(tag)
  @type tag_set :: keyword(value)

  @type value :: float | integer | boolean | String.t()
  @type field_key :: String.t() | atom()
  @type field :: {field_key, value}
  @type field_set :: nonempty_list(field)

  @type timestamp :: -9_223_372_036_854_775_806..9_223_372_036_854_775_806
  # @type point :: {measurement, tag_set, field_set, timestamp}

  @default_escapes [?,, ?=, ?\s]
  @measurement_escapes [?,, ?\s]
  @field_value_escapes [?"]

  # <measurement>[,<tag_key>=<tag_value>[,<tag_key>=<tag_value>]] <field_key>=<field_value>[,<field_key>=<field_value>] [<timestamp>]
  @spec encode({measurement, tag_set, field_set, timestamp | nil}) :: iodata
  def encode({measurement, tags, fields, timestamp}) do
    encode(measurement, tags, fields, timestamp)
  end

  @spec encode(measurement, tag_set, field_set) :: iodata
  def encode(measurement, tags, fields) do
    [
      escape_string(measurement, @measurement_escapes),
      encode_tags(tags),
      ?\s,
      encode_fields(fields)
    ]
  end

  @spec encode(measurement, tag_set, field_set, timestamp | nil) :: iodata
  def encode(measurement, tags, fields, nil) do
    encode(measurement, tags, fields)
  end

  def encode(measurement, tags, fields, timestamp) do
    [
      encode(measurement, tags, fields),
      ?\s,
      Integer.to_string(timestamp)
    ]
  end

  @spec encode_tags(tags :: tag_set) :: iodata
  def encode_tags([]) do
    []
  end

  def encode_tags([{key, value} | rest]) when is_binary(value) or is_atom(value) do
    [?,, escape_string(key), ?=, escape_string(value) | encode_tags(rest)]
  end

  def encode_tags([{key, value} | rest]) do
    cond do
      is_integer(value) ->
        [?,, escape_string(key), ?=, Integer.to_string(value) | encode_tags(rest)]

      is_float(value) ->
        [?,, escape_string(key), ?=, :io_lib_format.fwrite_g(value) | encode_tags(rest)]

      true ->
        encode_tags(rest)
    end
  end

  @spec encode_fields(field_set) :: iodata
  def encode_fields([field | rest]) do
    [encode_field(field) | encode_tailing_fields(rest)]
  end

  @spec encode_tailing_fields(list(field)) :: iodata
  def encode_tailing_fields([]) do
    []
  end

  def encode_tailing_fields([field | rest]) do
    [?,, encode_field(field) | encode_tailing_fields(rest)]
  end

  @spec encode_field(field) :: iodata
  def encode_field({key, value}) do
    [escape_string(key), ?=, encode_field_value(value)]
  end

  @doc false
  @spec encode_field_value(value) :: iodata
  def encode_field_value(value)

  def encode_field_value(float) when is_float(float) do
    :io_lib_format.fwrite_g(float)
  end

  def encode_field_value(integer) when is_integer(integer) do
    [Integer.to_string(integer), ?i]
  end

  def encode_field_value(string) when is_binary(string) do
    [?", escape_string(string, @field_value_escapes), ?"]
  end

  def encode_field_value(true) do
    "t"
  end

  def encode_field_value(false) do
    "f"
  end

  @doc false
  @spec escape_string(String.t() | atom()) :: iodata
  def escape_string(string, escape \\ @default_escapes)

  def escape_string(atom, escape) when is_atom(atom) do
    atom
    |> Atom.to_string()
    |> escape_string(escape)
  end

  def escape_string(string, escape) do
    escape_string(string, [], string, 0, 0, escape)
  end

  @spec escape_string(String.t(), list(), String.t(), integer, integer, list) :: iodata

  def escape_string(<<char::utf8, rest::binary>>, acc, original, skip, length, escape) do
    cond do
      char in escape ->
        part = binary_part(original, skip, length)
        escape_string(rest, [acc, part, ?\\, char], original, skip + length + 1, 0, escape)

      char <= 0x7F ->
        escape_string(rest, acc, original, skip, length + 1, escape)

      char <= 0x7FF ->
        escape_string(rest, acc, original, skip, length + 2, escape)

      char <= 0xFFFF ->
        escape_string(rest, acc, original, skip, length + 3, escape)

      true ->
        escape_string(rest, acc, original, skip, length + 4, escape)
    end
  end

  def escape_string(<<_char, rest::binary>>, acc, original, skip, length, escape) do
    part = binary_part(original, skip, length)
    escape_string(rest, [acc, part], original, skip + length + 1, 0, escape)
  end

  def escape_string(<<>>, [], original, _skip, _length, _escape) do
    original
  end

  def escape_string(<<>>, acc, original, skip, length, _escape) do
    part = binary_part(original, skip, length)

    [acc, part]
  end
end
