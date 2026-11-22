# Run from the project root with: bend test.bend
import Base
import ./tools/host.bend as Host

def report(result: U32 & (String & String)) -> IO(Unit):
  match result:
    case (0, (out, _)): IO.write(out)
    case (+code, (out, err)): IO.die(Unit, code, out ++ err)

def temporary_dir(r: U32 & (String & String)) -> IO(String):
  match r:
    case (0, (out, _)): IO.pure(String, String.trim_end(out))
    case (code, (_, err)): IO.die(String, code, err)

# A child runs the tests so cleanup also happens after a failed assertion,
# compiler error, or timeout. mktemp creates a fresh private directory.
def main() -> IO(Unit):
  do IO<Unit>:
    +bend : String <- Host.tool("BEND", "bend")
    IO.print("Building Wirequill")
    Host.command(bend, ["build.bend"])
    IO.print("Checking the generator and its imports")
    Host.command(bend, ["main.bend", "--check-only"])
    IO.print("Running protobuf and gRPC integration tests")
    tmp : U32 & (String & String) <- Host.run("mktemp", ["-d"], "", 10000)
    +work : String <- temporary_dir(tmp)
    result : Result<&1, &1, U32 & String, U32 & (String & String)> <-
      Process.run(bend, ["tests/suite.bend", work], "", 1048576, 300000)
    Host.command("rm", ["-r", "--", work])
    status : U32 & (String & String) <- IO.pass(U32 & (String & String), result)
    report(status)
