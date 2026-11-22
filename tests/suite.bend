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

def reject_option(protoc: String, include: String, dest: String, option: String, diagnostic: String) -> IO(Unit):
  rejects(protoc, ["--plugin=build/protoc-gen-proto", include, "--proto_opt=" ++ option, dest, "fixture.proto"], diagnostic)

def negative(+protoc: String, +fixtures: String, +dir: String) -> IO(Unit):
  +include = "-I" ++ fixtures
  +dest = "--proto_out=" ++ dir
  do IO<Unit>:
    rejects(protoc, ["--plugin=build/protoc-gen-proto", include, dest, "old.proto"], "Only proto3")
    reject_option(protoc, include, dest, "bogus", "Unknown generator parameter")
    reject_option(protoc, include, dest, "module=../escape", "single identifier")
    reject_option(protoc, include, dest, "module=Runtime", "support file")
    reject_option(protoc, include, dest, "module=a,module=b", "Duplicate generator parameter")
    absent(dir ++ "/schema.bend")

# Force the schema across multiple CodeGeneratorResponse.File records, then
# import definitions from opposite ends of the reconstructed module.
def declarations(+n: Nat) -> String:
  match n:
    case 0n: ""
    case 1n+p: "message Row" ++ Nat.show(p) ++ " { uint32 x = 1; }\n" ++ declarations(p)

def check_chunks(+bend: String, protoc: String, +fixtures: String, +dir: String) -> IO(Unit):
  do IO<Unit>:
    Host.write_text(fixtures ++ "/wide.proto", "syntax = \"proto3\";\n" ++ declarations(64n))
    generate(protoc, "wirequill", fixtures, dir, ["wide.proto"])
    +test_file : String = dir ++ "/chunk_check.bend"
    Host.write_text(test_file, "import Base\nimport ./schema.bend as S\ndef main() -> Maybe<&2, S.PB_Row0>:\n  do Maybe<&2, S.PB_Row0>:\n    bytes : List<&2, U32> <- S.PB_Row63.encode(S.PB_Row63{42})\n    S.PB_Row0.decode(bytes)\n")
    Host.command(bend, [test_file, "--check-only"])

def compatibility(+bend: String, +protoc: String, +fixtures: String, +dir: String, executable: String) -> IO(Unit):
  +plugin : String = "--plugin=build/protoc-gen-wirequill"
  +include = "-I" ++ fixtures
  +dest = "--wirequill_out=" ++ dir
  do IO<Unit>:
    Host.command(protoc, [plugin, include, dest, "--wirequill_opt=module=archive,preserve_unknown", "tree.proto"])
    Host.command(protoc, [plugin, include, dest, "--wirequill_opt=module=catalog,preserve_unknown", "fixture.proto"])
    absent(dir ++ "/schema.bend")
    generated_test(bend, "tests/compat/roundtrip.bend", dir, executable, Nil{})

def suite(+work: String) -> IO(Unit):
  +fixtures = work ++ "/fixtures"
  +tree = work ++ "/recursive"
  +grpc = work ++ "/grpc"
  +again = work ++ "/rpc-repeat"
  +compat = work ++ "/compat"
  +errors = work ++ "/errors"
  do IO<Unit>:
    +bend : String <- Host.tool("BEND", "bend")
    +protoc : String <- Host.tool("PROTOC", "protoc")
    Host.command("mkdir", [fixtures, work ++ "/messages", tree, grpc, again, errors, compat])
    Fixtures.write(fixtures)
    Host.command(bend, ["tests/descriptors.bend"])
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
    compatibility(bend, protoc, fixtures, compat, work ++ "/compat-test")
    check_chunks(bend, protoc, fixtures, compat)
    negative(protoc, fixtures, errors)
    IO.print("Protobuf interoperability, gRPC transport, and plugin error tests passed.")

def launch(args: List<String>) -> IO(Unit):
  match args:
    case [_, work]: suite(work)
    case _: IO.die(Unit, 1, "Run bend test.bend from the project root")

def main() -> IO(Unit):
  IO.bind(List<String>, Unit, IO.args(), launch)
