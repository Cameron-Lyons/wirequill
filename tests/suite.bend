import Base
import ../tools/host.bend as Host
import ./fixtures.bend as Fixtures

def require(ok: Bool, why: String) -> IO(Unit):
  match ok:
    case True{}: IO.pure(Unit, Unit{})
    case False{}: IO.die(Unit, 1, why)

def equal_files(a: String, +b: String) -> IO(Unit):
  do IO<Unit>:
    src : String <- Host.read_text(a)
    dst : String <- Host.read_text(b)
    require(String.eq(src, dst), "Generated support module differs: " ++ b)

def absent_result(path: String, r: Result<&1, &1, U32 & String, File>) -> IO(Unit):
  match r:
    case Fail{(2, _)}: IO.pure(Unit, Unit{})
    case Fail{(code, err)}: IO.die(Unit, code, "Checking " ++ path ++ ": " ++ err)
    case Done{f}:
      do IO<Unit>:
        File.close(f)
        IO.die(Unit, 1, "Unexpected generated file: " ++ path)

def absent(+path: String) -> IO(Unit):
  do IO<Unit>:
    r : Result<&1, &1, U32 & String, File> <- File.open(path, "r")
    absent_result(path, r)

def copy_text(from: String, to: String) -> IO(Unit):
  do IO<Unit>:
    s : String <- Host.read_text(from)
    Host.write_text(to, s)

def generated_test(+bend: String, src: String, +generated: String, +executable: String, args: List<String>) -> IO(Unit):
  do IO<Unit>:
    copy_text(src, generated ++ "/roundtrip.bend")
    Host.command(bend, [generated ++ "/roundtrip.bend", "-o", executable])
    result : U32 & (String & String) <- Host.run(executable, args, "", 20000)
    Host.checked(executable, result)

# Exercise the normal plugin discovery path. Verify the local alias is in place
# so another plugin on the developer's PATH cannot satisfy this test.
def generate(protoc: String, +alias: String, fixtures: String, dest: String, files: List<String>) -> IO(Unit):
  do IO<Unit>:
    path : String <- IO.try(String, IO.get_env("PATH"))
    Host.command("test", ["-x", "build/protoc-gen-" ++ alias])
    args : List<String> = ["PATH=build:" ++ path, protoc, "-I" ++ fixtures, "--" ++ alias ++ "_out=" ++ dest]
    Host.command("env", List.append(&1, String, args, files))

def check_listing(dir: String, result: U32 & (String & String)) -> IO(Unit):
  (code, outputs) = result
  (names, err) = outputs
  do IO<Unit>:
    Host.checked("ls", (code, ("", err)))
    require(String.eq(names, "grpc_runtime.bend\nmessage_values.bend\nruntime.bend\nschema.bend\n"),
      "Unexpected generated file list: " ++ dir)

def service_outputs(+first: String, again: String) -> IO(Unit):
  do IO<Unit>:
    listing : U32 & (String & String) <- Host.run("env", ["LC_ALL=C", "ls", "-1A", first], "", 10000)
    check_listing(first, listing)
    Host.command("diff", ["-qr", first, again])

def messages(+bend: String, +protoc: String, +work: String, +fixtures: String) -> IO(Unit):
  +dir = work ++ "/messages"
  do IO<Unit>:
    generate(protoc, "wirequill", fixtures, dir, ["fixture.proto"])
    absent(dir ++ "/grpc_runtime.bend")
    equal_files("runtime.bend", dir ++ "/runtime.bend")
    equal_files("message_values.bend", dir ++ "/message_values.bend")
    Host.command(bend, [dir ++ "/schema.bend", "--check-only"])
    Host.command(bend, ["tests/interop.bend", bend, protoc, work, fixtures, dir])

def check_failure(+expected: String, status: U32 & (String & String)) -> IO(Unit):
  (raw_code, outputs) = status
  (out, raw_err) = outputs
  +code : U32 = raw_code
  +err : String = raw_err
  failed = Bool.not(U32.is_zero(code))
  reason = "Expected diagnostic " ++ String.quote(expected) ++ ", got exit " ++ U32.show(code) ++ "\n" ++ err
  require(failed && String.is_empty(out) && String.contains(err, expected), reason)

def rejects(+protoc: String, args: List<String>, diagnostic: String) -> IO(Unit):
  do IO<Unit>:
    status : U32 & (String & String) <- Host.run(protoc, args, "", 20000)
    check_failure(diagnostic, status)

def negative(+protoc: String, +fixtures: String, +dir: String) -> IO(Unit):
  +include = "-I" ++ fixtures
  do IO<Unit>:
    rejects(protoc, ["--plugin=build/protoc-gen-grpc", include, "--grpc_out=" ++ dir, "upload.proto"], "client streaming")
    rejects(protoc, ["--plugin=build/protoc-gen-proto", include, "--proto_out=" ++ dir, "old.proto"], "Only proto3")
    rejects(protoc, ["--plugin=build/protoc-gen-proto", include, "--proto_opt=bogus", "--proto_out=" ++ dir, "fixture.proto"], "generator parameters")
    absent(dir ++ "/schema.bend")

def suite(+work: String) -> IO(Unit):
  +fixtures = work ++ "/fixtures"
  +tree = work ++ "/recursive"
  +grpc = work ++ "/grpc"
  +again = work ++ "/rpc-repeat"
  +errors = work ++ "/errors"
  do IO<Unit>:
    +bend : String <- Host.tool("BEND", "bend")
    +protoc : String <- Host.tool("PROTOC", "protoc")
    Host.command("mkdir", [fixtures, work ++ "/messages", tree, grpc, again, errors])
    Fixtures.write(fixtures)
    Host.command(bend, ["tests/runtime.bend", "-o", work ++ "/runtime-test"])
    Host.command(work ++ "/runtime-test", Nil{})
    messages(bend, protoc, work, fixtures)
    generate(protoc, "proto", fixtures, tree, ["tree.proto"])
    generated_test(bend, "tests/recursive/roundtrip.bend", tree, work ++ "/tree-test", Nil{})
    generate(protoc, "grpc", fixtures, grpc, ["echo.proto", "fixture.proto"])
    generate(protoc, "wirequill", fixtures, again, ["echo.proto", "fixture.proto"])
    service_outputs(grpc, again)
    equal_files("grpc_runtime.bend", grpc ++ "/grpc_runtime.bend")
    generated_test(bend, "tests/grpc/roundtrip.bend", grpc, work ++ "/grpc-test", [work ++ "/echo.sock"])
    negative(protoc, fixtures, errors)
    IO.print("Protobuf interoperability, gRPC transport, and plugin error tests passed.")

def launch(args: List<String>) -> IO(Unit):
  match args:
    case [_, work]: suite(work)
    case _: IO.die(Unit, 1, "Run bend test.bend from the project root")

def main() -> IO(Unit):
  IO.bind(List<String>, Unit, IO.args(), launch)
