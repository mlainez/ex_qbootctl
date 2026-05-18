defmodule ExQbootctl do
  @moduledoc """
  Thin Elixir wrapper around `qbootctl`, the userspace A/B-slot HAL for
  Qualcomm devices. Provides the public API and a supervised marker
  process that calls `qbootctl -m` once boot has stabilised, so the
  bootloader stops decrementing the retry counter and falling back to
  fastboot after enough reboots.

  ## How it works

  Qualcomm bootloaders use A/B partitioning with per-slot metadata:

      * `successful_boot` — set to 1 when userspace confirms it booted
      * `tries_remaining` — decremented every boot until set successful

  If `tries_remaining` hits 0 without `successful_boot` being set, the
  bootloader marks the slot unbootable and tries the other one. If
  neither is bootable, it drops into fastboot.

  Without `qbootctl -m` in userspace, every Nerves firmware boot looks
  like a failure to the bootloader. The retry budget runs out within a
  handful of reboots and the device becomes "dead" (stuck in fastboot)
  until manually rescued via EDL or USB.

  This library starts a supervised process that waits a configurable
  delay after boot (default 7 s) and then marks the slot successful.
  The delay is important: if the firmware crashes hard before the
  delay elapses, *that* boot is not marked successful, so the
  bootloader will eventually fall back as designed.

  ## Configuration

      config :ex_qbootctl,
        delay_ms: 7_000         # how long after boot before marking
        # auto_mark: true       # set to false to disable the marker

  ## Usage

      iex> ExQbootctl.info()
      {:ok, "Current slot: _b\\nSlot _a: ...\\n..."}

      iex> ExQbootctl.current_slot()
      {:ok, "_b"}

      iex> ExQbootctl.mark_successful()
      :ok
  """
  require Logger

  @qbootctl "/usr/bin/qbootctl"

  @doc "Dump slot info (runs `qbootctl` with no args)."
  @spec info() :: {:ok, String.t()} | {:error, term()}
  def info, do: run([])

  @doc "Return the current slot suffix (e.g. `\"_a\"` or `\"_b\"`)."
  @spec current_slot() :: {:ok, String.t()} | {:error, term()}
  def current_slot do
    case run(["-c"]) do
      {:ok, out} -> {:ok, String.trim(out)}
      err -> err
    end
  end

  @doc """
  Mark the current slot as a successful boot. Idempotent — safe to call
  multiple times. Returns `:ok` (the qbootctl command swallows useful
  output but exits 0 on success) or `{:error, {exit, output}}`.
  """
  @spec mark_successful() :: :ok | {:error, term()}
  def mark_successful do
    case run(["-m"]) do
      {:ok, _} -> :ok
      err -> err
    end
  end

  @doc """
  Set the active slot. Usually called by an update tool right after
  writing the new slot's partitions, not by application code at runtime.
  """
  @spec set_active(String.t()) :: :ok | {:error, term()}
  def set_active(slot) when slot in ["_a", "_b", "a", "b"] do
    case run(["-s", slot]) do
      {:ok, _} -> :ok
      err -> err
    end
  end

  ## Internals

  defp run(args) do
    case System.cmd(@qbootctl, args, stderr_to_stdout: true) do
      {out, 0} -> {:ok, out}
      {out, code} -> {:error, {code, String.trim(out)}}
    end
  end
end
