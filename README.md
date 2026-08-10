# ex_qbootctl

> ### ⚠️ Very early work — built for a workshop, not for production
>
> Written for the **Goatmire Elixir workshop** on running Nerves on
> Fairphone 3 hardware. It exists for tinkering and teaching.
>
> **Not an actively maintained project** (yet) — no stability
> guarantees, no test coverage, APIs will change without notice.

Elixir wrapper around `qbootctl`, the userspace A/B-slot HAL for
Qualcomm devices.

**If you are running Nerves on a Qualcomm A/B device, you probably need
this or an equivalent.** Without it your device will eventually stop
booting your firmware and drop into fastboot.

## Why

Qualcomm bootloaders use A/B partitioning with per-slot metadata:

- `successful_boot` — set to 1 when userspace confirms it booted
- `tries_remaining` — decremented on every boot until marked successful

If `tries_remaining` reaches 0 without `successful_boot` being set, the
bootloader marks that slot unbootable and switches to the other one. If
neither is bootable, it falls back to fastboot.

Nothing in a stock Nerves image tells the bootloader that boot succeeded.
So **every** boot looks like a failure, the retry budget drains over a
handful of reboots, and the device stops booting your firmware — usually
at the least convenient moment.

This library runs `qbootctl -m` from a supervised process once boot has
stabilised, which resets the counter.

## Install

```elixir
defp deps do
  [{:ex_qbootctl, github: "mlainez/ex_qbootctl"}]
end
```

Requires the `qbootctl` binary in the Nerves system.

## Usage

Add it to your supervision tree and it marks the slot successful on its
own. Manual control:

```elixir
ExQbootctl.info            # full slot metadata
ExQbootctl.current_slot    # "_a" | "_b"
ExQbootctl.mark_successful # what the supervised process calls
ExQbootctl.set_active("_b")
```

## License

Apache-2.0
