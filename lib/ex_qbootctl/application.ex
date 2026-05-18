defmodule ExQbootctl.Application do
  @moduledoc false
  use Application

  @impl true
  def start(_type, _args) do
    children =
      if Application.get_env(:ex_qbootctl, :auto_mark, true) do
        [ExQbootctl.Marker]
      else
        []
      end

    Supervisor.start_link(children, strategy: :one_for_one, name: ExQbootctl.Supervisor)
  end
end
