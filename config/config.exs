use Mix.Config

case Mix.env do
  :test ->
    config :logger, level: :error
    config :terminus, scheme: :http, port: 8088
  :dev ->
    config :logger, level: :info
  _ ->
    true
end