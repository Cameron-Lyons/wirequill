import Base
import bend-kit-process@0.5.2.1/process.bend as Proc
import bend-kit-bytes@0.3.3.1/bytes.bend as Bytes
import bend-kit-protobuf@0.2.2.0/protobuf.bend as P
import ../tools/host.bend as Host
import ./fixtures.bend as Fixtures

# Proc's raw interface represents each octet as one character, so binary data
# passes unchanged between protoc and the generated Bend codec, including NULs.
def succeeded(program: String, result: U32 & String & String) -> IO(String):
  match result:
    case (0, out, _): IO.pure(String, out)
    case (code, _, err): IO.die(String, code, program ++ " failed: " ++ err)

def pipe(+program: String, args: List<&2, String>, octets: String) -> IO(String):
  do IO<String>:
    result : U32 & String & String <- IO.try(U32 & String & String,
      Proc.run.bounded.raw(program, args, Nil{}, ".", octets, 20000, 1048576))
    succeeded(program, result)

def utf8_bytes(r: Result<&2, &1, P.Error, Bytes.Bytes>) -> IO(String):
  match r:
    case Done{b}: IO.pure(String, Bytes.to_string(b))
    case Fail{_}: IO.die(String, 1, "invalid Unicode in textproto fixture")

def encode(protoc: String, include: String, input: String) -> IO(String):
  do IO<String>:
    text : String <- utf8_bytes(P.utf8.encode(input))
    pipe(protoc, [include, "--encode=sample.Item", "fixture.proto"], text)

def decode(protoc: String, include: String, wire: String) -> IO(String):
  pipe(protoc, [include, "--decode=sample.Item", "fixture.proto"], wire)

def check(ok: Bool, reason: String) -> IO(Unit):
  match ok:
    case True{}: IO.pure(Unit, Unit{})
    case False{}: IO.die(Unit, 1, reason)

def run(bend: String, +protoc: String, work: String, fixtures: String, messages: String) -> IO(Unit):
  +include = "-I" ++ fixtures
  +source = messages ++ "/roundtrip.bend"
  +app = work ++ "/interop"
  do IO<Unit>:
    original : String <- Host.read_text("tests/proto/roundtrip.bend")
    Host.write_text(source, original)
    Host.command(bend, [source, "-o", app])
    before : String <- encode(protoc, include, Fixtures.item_text())
    changed : String <- pipe(app, Nil{}, before)
    actual : String <- decode(protoc, include, changed)
    wanted : String <- encode(protoc, include, Fixtures.item_with_count(7))
    expected : String <- decode(protoc, include, wanted)
    check(String.eq(actual, expected), "protoc decoded a different message after the Bend update")

def check_malformed(result: U32 & String & String) -> IO(Unit):
  match result:
    case (code, out, err):
      check(Bool.not(U32.is_zero(code)) && String.is_empty(out) && String.contains(err, "Malformed CodeGeneratorRequest"),
        "plugin failed to reject a truncated binary request cleanly")

def malformed(plugin: String) -> IO(Unit):
  do IO<Unit>:
    result : U32 & String & String <- IO.try(U32 & String & String,
      Proc.run.bounded.raw(plugin, Nil{}, Nil{}, ".", SCon{Chr{128}, SNil{}}, 20000, 1048576))
    check_malformed(result)

# Run the byte-pipe driver with the Bend CLI. The plugin and the generated
# codec executable it exchanges data with are both native programs.
def launch(args: List<String>) -> IO(Unit):
  match args:
    case [_, bend, protoc, work, fixtures, messages]:
      do IO<Unit>:
        run(bend, protoc, work, fixtures, messages)
        malformed("build/wirequill")
    case _: IO.die(Unit, 1, "Run bend test.bend from the project root")

def main() -> IO(Unit):
  IO.bind(List<String>, Unit, IO.args(), launch)
