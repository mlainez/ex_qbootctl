defmodule ExQbootctl do
  @moduledoc """
  Thin Elixir wrapper around [`qbootctl`](https://github.com/linux-msm/qbootctl),
  the userspace A/B-slot HAL for Qualcomm devices, plus a marker process
  that runs `qbootctl -m` once boot has stabilised.

  ## Why

  Qualcomm bootloaders keep per-slot metadata in the GPT:

    * `successful` — set when userspace confirms the slot booted
    * a retry counter — decremented on every boot until the slot is marked
      successful

  If the counter runs out the bootloader marks the slot unbootable and tries
  the other one; with neither bootable it drops into fastboot. Nothing in a
  stock Nerves image marks the boot successful, so every boot looks like a
  failure until the device ends up in fastboot.

  ## Start model

  The `:ex_qbootctl` application starts automatically. Unless disabled it
  runs `ExQbootctl.Marker`, which waits `:delay_ms` and then calls
  `mark_successful/0`. The delay is the safety margin: if the firmware
  crashes hard before it elapses, that boot is not marked successful and the
  bootloader can fall back as designed.

  ## Configuration

      config :ex_qbootctl,
        auto_mark: true,                     # default; false disables the marker
        delay_ms: 7_000,                     # default
        qbootctl_path: "/usr/bin/qbootctl"   # default

  ## Usage

      ExQbootctl.info()
      #=> {:ok, "Current slot: _b\\nSLOT _a:\\n\\tActive      : 0\\n..."}

      ExQbootctl.current_slot()
      #=> {:ok, "_b"}

      ExQbootctl.mark_successful()
      #=> :ok

  Every function returns `{:error, :enoent}` if the binary is missing and
  `{:error, {exit_status, output}}` if `qbootctl` fails. `qbootctl` must run
  as root.
  """

  @default_path "/usr/bin/qbootctl"

  @type slot :: String.t()

  @doc "Dump slot info (runs `qbootctl` with no args) and return its output."
  @spec info() :: {:ok, String.t()} | {:error, term()}
  def info, do: run([])

  @doc """
  Return the current slot suffix, `"_a"` or `"_b"`.

  Parses the `Current slot: _b` line printed by `qbootctl -c`.
  """
  @spec current_slot() :: {:ok, slot()} | {:error, term()}
  def current_slot do
    with {:ok, out} <- run(["-c"]) do
      case Regex.run(~r/Current slot:\s*(_[ab])/, out) do
        [_, slot] -> {:ok, slot}
        nil -> {:error, {:unexpected_output, String.trim(out)}}
      end
    end
  end

  @doc """
  Mark the current slot as a successful boot (`qbootctl -m`). Idempotent:
  `qbootctl` exits 0 when the slot is already marked.
  """
  @spec mark_successful() :: :ok | {:error, term()}
  def mark_successful do
    with {:ok, _} <- run(["-m"]), do: :ok
  end

  @doc """
  Set the active slot (`qbootctl -s`). Accepts `"_a"`, `"_b"`, `"a"` or
  `"b"`; anything else returns `{:error, :invalid_slot}` without running
  `qbootctl`.

  Usually called by an update tool right after writing the new slot's
  partitions, not by application code at runtime.
  """
  @spec set_active(String.t()) :: :ok | {:error, term()}
  def set_active(slot) do
    # qbootctl 0.2.2 only accepts a/b/A/B/0/1 as the slot argument.
    case slot do
      s when s in ["_a", "a"] -> set_active_raw("a")
      s when s in ["_b", "b"] -> set_active_raw("b")
      _ -> {:error, :invalid_slot}
    end
  end

  defp set_active_raw(slot) do
    with {:ok, _} <- run(["-s", slot]), do: :ok
  end

  ## Internals

  defp run(args) do
    path = Application.get_env(:ex_qbootctl, :qbootctl_path, @default_path)

    case System.find_executable(path) do
      nil ->
        {:error, :enoent}

      exe ->
        case System.cmd(exe, args, stderr_to_stdout: true) do
          {out, 0} -> {:ok, out}
          {out, code} -> {:error, {code, String.trim(out)}}
        end
    end
  end
end
