defmodule ExQbootctl.Marker do
  @moduledoc """
  Waits `:delay_ms` (default `7_000`) after it starts, then calls
  `ExQbootctl.mark_successful/0` once and logs the result.

  The delay is the safety margin — if the firmware crashes hard within
  that window, the slot is never marked successful and the bootloader
  is free to fall back to the other slot on the next boot. Pick it
  long enough that everything you care about (network, modem, camera,
  …) has had a chance to come up.

  A failure (missing binary, non-zero exit) is logged as a warning; the
  process does not crash or retry.
  """
  use GenServer
  require Logger

  @default_delay_ms 7_000

  @doc false
  def start_link(_), do: GenServer.start_link(__MODULE__, [], name: __MODULE__)

  @impl true
  def init(_) do
    delay = Application.get_env(:ex_qbootctl, :delay_ms, @default_delay_ms)
    Logger.info("ex_qbootctl: will mark boot successful in #{delay} ms")
    Process.send_after(self(), :mark, delay)
    {:ok, %{marked: nil}}
  end

  @impl true
  def handle_info(:mark, state) do
    result = ExQbootctl.mark_successful()

    case result do
      :ok ->
        Logger.info("ex_qbootctl: boot marked successful")

      {:error, reason} ->
        Logger.warning("ex_qbootctl: mark_successful failed: #{inspect(reason)}")
    end

    {:noreply, %{state | marked: result}}
  end
end
