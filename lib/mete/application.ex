defmodule Mete.Application do
  use Application

  def start(_type, _args) do
    Supervisor.start_link([Mete.Connection], strategy: :one_for_one)
  end
end
