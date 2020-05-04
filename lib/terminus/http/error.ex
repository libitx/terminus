defmodule Terminus.HTTP.Error do
  @moduledoc false
  defexception [:status]
  
  def message(exception),
    do: "HTTP Error: #{:httpd_util.reason_phrase(exception.status)}"
end