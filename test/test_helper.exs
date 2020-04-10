ExUnit.start()

Supervisor.start_link([
  {Plug.Cowboy, [
    scheme: :http,
    plug: MockServer,
    options: [port: 8088]
  ]}
], [strategy: :one_for_one])
