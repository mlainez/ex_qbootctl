defmodule ExQbootctlTest do
  use ExUnit.Case, async: false

  @moduletag :tmp_dir

  # Mimics the output of qbootctl 0.2.2 (linux-msm/qbootctl, qbootctl.c).
  @fake """
  #!/bin/sh
  echo "$*" >> "$(dirname "$0")/calls"
  case "$1" in
    "")
      printf 'Current slot: _b\\nSLOT _a:\\n\\tActive      : 0\\n'
      ;;
    -c) echo "Current slot: _b" ;;
    -m) echo "SLOT _b: Marked boot successful" ;;
    -s)
      case "$2" in
        a|b) echo "SLOT 1: Set as active slot" ;;
        *) echo "Expected slot not '$2'" >&2; exit 1 ;;
      esac
      ;;
  esac
  """

  setup %{tmp_dir: dir} do
    on_exit(fn -> Application.delete_env(:ex_qbootctl, :qbootctl_path) end)
    %{dir: dir}
  end

  defp install(dir, body) do
    path = Path.join(dir, "qbootctl")
    File.write!(path, body)
    File.chmod!(path, 0o755)
    Application.put_env(:ex_qbootctl, :qbootctl_path, path)
    path
  end

  defp calls(dir), do: dir |> Path.join("calls") |> File.read!() |> String.split("\n", trim: true)

  test "info/0 returns the raw dump", %{dir: dir} do
    install(dir, @fake)
    assert {:ok, "Current slot: _b\n" <> _} = ExQbootctl.info()
    assert File.read!(Path.join(dir, "calls")) == "\n"
  end

  test "current_slot/0 parses `qbootctl -c` output", %{dir: dir} do
    install(dir, @fake)
    assert {:ok, "_b"} = ExQbootctl.current_slot()
    assert calls(dir) == ["-c"]
  end

  test "current_slot/0 reports unexpected output", %{dir: dir} do
    install(dir, "#!/bin/sh\necho garbage\n")
    assert {:error, {:unexpected_output, "garbage"}} = ExQbootctl.current_slot()
  end

  test "mark_successful/0 runs -m", %{dir: dir} do
    install(dir, @fake)
    assert :ok = ExQbootctl.mark_successful()
    assert calls(dir) == ["-m"]
  end

  test "set_active/1 translates suffixes to what qbootctl accepts", %{dir: dir} do
    install(dir, @fake)
    assert :ok = ExQbootctl.set_active("_b")
    assert :ok = ExQbootctl.set_active("a")
    assert calls(dir) == ["-s b", "-s a"]
  end

  test "set_active/1 rejects bad input without running qbootctl", %{dir: dir} do
    install(dir, @fake)
    assert {:error, :invalid_slot} = ExQbootctl.set_active("_c")
    assert {:error, :invalid_slot} = ExQbootctl.set_active(:b)
    refute File.exists?(Path.join(dir, "calls"))
  end

  test "non-zero exit returns {:error, {status, output}}", %{dir: dir} do
    install(dir, "#!/bin/sh\necho 'This program must be run as root!' >&2\nexit 1\n")
    assert {:error, {1, "This program must be run as root!"}} = ExQbootctl.mark_successful()
  end

  test "missing binary returns {:error, :enoent}", %{dir: dir} do
    Application.put_env(:ex_qbootctl, :qbootctl_path, Path.join(dir, "missing"))
    assert {:error, :enoent} = ExQbootctl.info()
    assert {:error, :enoent} = ExQbootctl.current_slot()
    assert {:error, :enoent} = ExQbootctl.mark_successful()
    assert {:error, :enoent} = ExQbootctl.set_active("_a")
  end

  describe "Marker" do
    setup do
      Application.put_env(:ex_qbootctl, :delay_ms, 10)
      on_exit(fn -> Application.delete_env(:ex_qbootctl, :delay_ms) end)
    end

    test "marks the boot successful after the delay", %{dir: dir} do
      install(dir, @fake)
      pid = start_supervised!(ExQbootctl.Marker)
      Process.sleep(100)
      assert %{marked: :ok} = :sys.get_state(pid)
      assert calls(dir) == ["-m"]
    end

    test "survives a missing binary", %{dir: dir} do
      Application.put_env(:ex_qbootctl, :qbootctl_path, Path.join(dir, "missing"))
      pid = start_supervised!(ExQbootctl.Marker)
      Process.sleep(100)
      assert %{marked: {:error, :enoent}} = :sys.get_state(pid)
    end
  end

  test "the application does not start the marker when auto_mark is false" do
    assert Supervisor.which_children(ExQbootctl.Supervisor) == []
  end
end
