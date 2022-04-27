defmodule Mete do
  @moduledoc """
  [*/miːt/*] - Old English metan 'measure'

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
  - `:tags` - can be used to configure application-wide tags expects a Keywordlist of strings or atoms, defaults to `[]`
  - `:batch` - InfluxDB supports batching measurements, can be deactivated with `false` activated with `true` or directly configure the byte-size of the payloads with an integer
  - `:compression` - defaults to `nil` and can be set to `:gzip` only for http
  - `:database` - has to be configured when using `:http` (InfluxDB v1)
  - `:bucket` - bucket id for your target bucket (InfluxDB v2)
  - `:organistaion` - your organisation id (InfluxDB v2)
  - `:token` - your access token (InfluxDB v2)

  ### Example for InfluxDB v2
  ```
    config :mete,
      influx_version: 2
      organisation: "ORGANISATION-ID",
      host: "some-cloud.influxdata.com",
      bucket: "BUCKET-ID",
      token: "YOUR-TOKEN",
      batch: 10_000
      path: "/api/v2/write",
      port: nil,
      protocol: :http,
      scheme: "https",
  ```


  ## ToDo
  - Configurable handling of integer/float values.
  - Configurable handling of timestamps
  - Support for mfa's for measure.
  - base default batch size on connection parameters
  """
  import Mete.Utils

  # , only: [into_tags: 2, into_tags: 3]

  require Logger

  alias Mete.Protocol

  @type measurement :: Protocol.measurement()
  @type tags :: Protocol.tag_set()
  @type fields :: Protocol.field_set()
  @type value :: Protocol.value()
  @type timestamp :: Protocol.timestamp()

  @tags :__mete_tags__
  @measure_points :__mete_measuring_points__

  @doc """
  Writes a single measurement.
  A measurement consists of a measurement, tags and fields.

  Requires a name of the measurement either as a string or atom.
  Atoms are always converted to strings.
  Tags can be given either as a keyword list of strings or atoms, or tuple lists with string keys.

  Fields can be either atoms, strings, boolean, integer, or floats.
  If measurements are not known to influx the according table will be created or altered.
  If a field should change its value from integer or float (or any other type) for some reason this will lead to datalos since the new fields wont match the present table.

  ### Examples:

      iex> write("temp", [region: "EU", foo: "bar"], c: 42.0, f: 107.6)
      :ok

  If the value is without a name it defaults to `:value` thus ...

      iex> write("temp", 42)
      :ok

  is equivalent to ...

      iex> write("temp", value: 42)
      :ok

  """
  @spec write(measurement, tags, fields | value) :: :ok
  def write(measurement, tags \\ [], fields)

  def write(measurement, tags, fields) when is_list(fields) do
    __write__(measurement, tags, fields, nil)
  end

  def write(measurement, tags, value) do
    __write__(measurement, tags, [{:value, value}], nil)
  end

  @doc """
  Evaluates the given function, measures, and subsequently writes the elapsed real time.

      iex> measure("query", fn -> "some query result" end)
      "some query result"
  """
  @spec measure(measurement, tags, fields | [], (() -> any())) :: any()
  def measure(measurement, tags \\ [], fields \\ [], func) when is_function(func, 0) do
    {value, result} = :timer.tc(func)
    __write__(measurement, tags, [{:value, value} | fields], nil)
    result
  end

  @doc """
  Adds a meter point under the given atom to the process.
  """
  def meter(field) do
    measure_points =
      @measure_points
      |> Process.get([])
      |> Keyword.merge([{field, timestamp()}])

    Process.put(@measure_points, measure_points)
    :ok
  end

  @doc """
  Calculates the delta for the process meter points and writes them under the measurement.
  """
  def write_meter(measurement, tags \\ []) do
    timestamp = timestamp()

    case Process.get(@measure_points) do
      nil ->
        Logger.warn(["No meter points found for ", inspect(measurement)])

      meter_points ->
        Process.put(@measure_points, [])
        delta = Enum.map(meter_points, fn {key, value} -> {key, timestamp - value} end)

        __write__(measurement, tags, delta, timestamp)
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

  @spec __write__(measurement, tags, fields, timestamp | nil) :: :ok | :error
  defp __write__(measurement, tags, fields, timestamp) do
    case __tags__() do
      {true, p_tags} ->
        case :ets.tab2list(Mete) do
          [] ->
            :error

          connections ->
            {pid} = Enum.random(connections)

            GenServer.cast(
              pid,
              {:write, {measurement, into_tags(tags, p_tags), fields, timestamp || timestamp()}}
            )
        end

      _ ->
        :error
    end
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
