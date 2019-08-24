url = 'http://localhost:8086/write?db=mydb'
# url = 'http://localhost:8086/query'

Mete.tags(pid: inspect(self()))

# GenServer.start_link(Mete.Connection, [], name: Mete.Connection)

# data =
#   Mete.Protocol.encode(
#     "query",
#     [{"country", "us"}, {"region", "west"}],
#     [
#       {"exec", 12.0},
#       {"queue", 33},
#       {"ok?", true},
#       {"not ok?", false},
#       {"hi", "world"}
#     ]
#   )

#   |> IO.iodata_to_binary()

# IO.inspect(:httpc.request(:post, {url, [], 'text-plain', data}, [], []))

Mete.write(
  "udp_stuff",
  [{"country", "us"}, {"region", "west"}],
  [
    {"exec", 12.0},
    {"queue", 33},
    {"ok?", true},
    {"not ok?", false},
    {"hi", "world"}
  ]
)
