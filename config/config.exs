use Mix.Config

case Mix.env do
  :test ->
    config :logger, level: :error
    config :terminus,
      scheme: :http,
      port: 8088,
      token: "test"

  _ ->
    config :logger, level: :info
end
