#    Mete is a basic measuring tool and telemetry writer for elixir using InfluxDB.
#    Copyright (C) 2019  Hans Bernhard Goedeke
#
#    This program is free software: you can redistribute it and/or modify
#    it under the terms of the GNU General Public License as published by
#    the Free Software Foundation, either version 3 of the License, or
#    (at your option) any later version.
#
#    This program is distributed in the hope that it will be useful,
#    but WITHOUT ANY WARRANTY; without even the implied warranty of
#    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#    GNU General Public License for more details.
#
#    You should have received a copy of the GNU General Public License
#    along with this program.  If not, see <https://www.gnu.org/licenses/>.

defmodule Mete do
  @moduledoc """
  Basic measuring tool and telemetry writer using InfluxDB.

  ## Usage
  Add Mete to your application by adding `{:mete, "~> #{Mix.Project.config()[:version]}"}` to your list of dependencies in `mix.exs`:
  ```elixir
  def deps do
    [
      # ...
      {:mete, "~> #{Mix.Project.config()[:version]}"}
    ]
  end
  ```

  ## Options
  - `:host` - hostname of the server running the InfluxDB endpoint, defaults to `localhost`
  - `:port` - port on which the InfluxDB server runs the respective input, defaults to `8089`
  - `:protocol` - either `:udp`, or `:http`.  Defaults to `:udp`.
  - `:database` - has to be configured when using `:http`
  - `:tags` - can be used to configure application-wide tags expects a Keywordlist of strings or atoms, defaults to `[]`

  ## ToDo
  - Configurable handling of integer/float values.
  - Configurable handling of timestamps
  - Support for mfa's for measure.
  """
  alias Mete.Protocol

  import Mete.Utils, only: [into_tags: 2, into_tags: 3]

  @type measurement :: Protocol.measurement()
  @type tags :: Protocol.tag_set()
  @type fields :: Protocol.field_set()
  @type value :: Protocol.value()
  @type timestamp :: Protocol.timestamp()

  @tags :__mete_tags__

  @spec write(measurement, tags, fields | value) :: :ok
  @doc """
  Writes a measurement.

      write("query", [exec: 20, queue: 33])
  """
  def write(measurement, tags \\ [], fields)

  def write(measurement, tags, fields) when is_list(fields) do
    __write__(measurement, tags, fields, nil)
  end

  def write(measurement, tags, value) do
    __write__(measurement, tags, [{:value, value}], nil)
  end

  @spec measure(measurement, tags, list(Protocol.field()), (() -> any())) :: any()
  @doc """
  Evaluates the given function, measures, and subsequently writes the elapsed real time.

      iex> measure("query", fn -> "some query result" end)
      "some query result"
  """
  def measure(measurement, tags, fields \\ [], func) when is_function(func, 0) do
    {value, result} = :timer.tc(func)
    __write__(measurement, tags, [{:value, value} | fields], nil)
    result
  end

  @spec __write__(measurement, tags, fields, timestamp | nil) :: :ok | :error
  defp __write__(measurement, tags, fields, timestamp) do
    case __tags__() do
      {true, p_tags} ->
        GenServer.cast(
          __MODULE__,
          {:write, {measurement, into_tags(tags, p_tags), fields, timestamp || timestamp()}}
        )

      _ ->
        :error
    end
  end

  @doc """
  Alters the current process tags according the given keyword list.

  The given keyword list will be merged into the existing tags,
  tags set to `nil` will remove that tag from the tag list.
  """
  @spec tags(tags) :: :ok
  def tags(keyword) do
    {enabled?, tags} = __tags__()
    Process.put(@tags, {enabled?, into_tags(keyword, tags)})
    :ok
  end

  @doc """
  Reads the current process tags.
  """
  @spec tags() :: tags
  def tags do
    elem(__tags__(), 1)
  end

  @compile {:inline, __tags__: 0}
  defp __tags__ do
    Process.get(@tags) || {true, []}
  end

  defp timestamp do
    :os.system_time(:nanosecond)
  end

  # @unix_epoch 62_167_219_200

  # defp timestamp do
  #   {_, _, micro} = now = :os.timestamp()
  #   {date, {hours, minutes, seconds}} = :calendar.now_to_universal_time(now)

  #   timestamp_to_unix({date, {hours, minutes, seconds, micro}})
  # end

  # defp timestamp_to_unix({date, {hour, minute, second, micro}}) do
  #   timestamp_to_unix({date, {hour, minute, second}}) * 1_000_000_000 + micro * 1_000
  # end

  # defp timestamp_to_unix({_d, {_h, _m, _s}} = datetime) do
  #   :calendar.datetime_to_gregorian_seconds(datetime) - @unix_epoch
  # end
end
