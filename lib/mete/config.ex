defmodule Mete.Config do
  @moduledoc false

  defstruct [
    :bucket,
    :database,
    :organisation,
    :token,
    batch: true,
    host: "localhost",
    influx_version: 1,
    path: "/write",
    port: 8089,
    scheme: "http",
    tags: [],
    protocol: :udp
  ]

  def config do
    env_config = Application.get_all_env(:mete)

    struct(__MODULE__, env_config)
  end

  def config(args) do
    struct(config(), args)
  end

  ##  Callbacks

  def batch_size(config, adapter)

  def batch_size(%__MODULE__{batch: true}, %adapter_module{} = adapter) do
    apply(adapter_module, :batch_size, [adapter])
  end

  def batch_size(%__MODULE__{batch: batch_size}, _) when is_integer(batch_size) do
    batch_size
  end

  def batch_size(_config, _adapter) do
    nil
  end

  def uri(%__MODULE__{influx_version: 1} = config) do
    %URI{
      host: config.host,
      path: config.path,
      port: config.port,
      scheme: config.scheme
    }
    |> Map.put(:query, URI.encode_query(%{"db" => config.database}))
    |> URI.to_string()
  end

  def uri(%__MODULE__{influx_version: 2} = config) do
    query = %{"bucket" => config.bucket, "org" => config.organisation, "precision" => "ns"}

    %URI{
      host: config.host,
      path: config.path,
      port: config.port,
      scheme: config.scheme
    }
    |> Map.put(:query, URI.encode_query(query))
    |> URI.to_string()
  end

  def adapter_module(protocol)

  def adapter_module(:udp), do: Mete.Connection.Udp

  def adapter_module(:http), do: Mete.Connection.Httpc

  def adapter_module(module), do: module
end
