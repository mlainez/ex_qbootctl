# ex_qbootctl

> ### ⚠️ Very early work — built for a workshop, not for production
>
> Written for the **Goatmire Elixir workshop** on running Nerves on Fairphone 3 hardware. There are no stability guarantees and APIs will change without notice.

Elixir wrapper around [`qbootctl`](https://github.com/linux-msm/qbootctl),
the userspace A/B-slot HAL for Qualcomm devices.

**If you are running Nerves on a Qualcomm A/B device, you probably need
this or an equivalent.** Without it your device will eventually stop
booting your firmware and drop into fastboot.

## Why

Qualcomm bootloaders use A/B partitioning with per-slot metadata in the
GPT:

- a `successful` flag, set when userspace confirms the slot booted
- a retry counter, decremented on every boot until the slot is marked
  successful

If the counter runs out without the slot being marked successful, the
bootloader marks it unbootable and switches to the other slot. If neither
is bootable, it falls back to fastboot.

Nothing in a stock Nerves image tells the bootloader that boot succeeded.
So **every** boot looks like a failure, the retry budget drains over a
handful of reboots, and the device stops booting your firmware — usually
at the least convenient moment.

This library runs `qbootctl -m` once boot has stabilised.

## Install

```elixir
defp deps do
  [{:ex_qbootctl, github: "mlainez/ex_qbootctl"}]
end
```

Requires the `qbootctl` binary (0.2.2, `packages/qbootctl` in
`nerves_system_fp3`, installed at `/usr/bin/qbootctl`). It must run as
root, which is the default on Nerves.

## Usage

The application starts automatically; there is nothing to add to your
supervision tree. It starts `ExQbootctl.Marker`, which waits `:delay_ms`
and then runs `qbootctl -m` once. If the firmware crashes before the delay
elapses, that boot is not marked successful and the bootloader can fall
back as designed. Failures are logged, never raised.

```elixir
config :ex_qbootctl,
  auto_mark: true,                     # default; false disables the marker
  delay_ms: 7_000,                     # default
  qbootctl_path: "/usr/bin/qbootctl"   # default
```

Manual control:

```elixir
ExQbootctl.info()             # {:ok, raw `qbootctl` dump}
ExQbootctl.current_slot()     # {:ok, "_a" | "_b"}, parsed from `qbootctl -c`
ExQbootctl.mark_successful()  # :ok (what the marker calls)
ExQbootctl.set_active("_b")   # :ok; "_a" | "_b" | "a" | "b", else {:error, :invalid_slot}
```

Errors are `{:error, :enoent}` when the binary is missing and
`{:error, {exit_status, output}}` when `qbootctl` fails.

## Status

Tested on the host against a fake `qbootctl` script that mimics the 0.2.2
output. Behaviour on the Fairphone 3 has not been re-verified since these
changes (in particular the `current_slot/0` parsing and the `set_active/1`
argument translation, which follow the 0.2.2 source).

## Toolchain

Built and tested with Erlang/OTP 29.1.1 and Elixir 1.20.4, matching the official Nerves systems (see `.tool-versions`).

## License

Apache-2.0
