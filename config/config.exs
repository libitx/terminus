use Mix.Config

case Mix.env do
  :test ->
    config :logger, level: :error
    config :terminus, scheme: :http, port: 8088
  _ ->
    config :terminus, scheme: :https, port: 443
end