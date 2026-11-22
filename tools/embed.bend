# Embed each support module as short string literals. Walk the source once
# so long lines and large modules fit the Bend compiler's stack.
import Base
import ./host.bend as Host

def wrote(pair: File & Result<&1, &1, U32 & String, Unit>) -> IO(File):
  (f, result) = pair
  do IO<File>:
    ok : Unit <- IO.pass(Unit, result)
    return f

def write(f: File, text: String) -> IO(File):
  IO.bind(File & Result<&1, &1, U32 & String, Unit>, File, File.write(f, text), wrote)

def literal(reversed: String) -> String:
  "    " ++ String.quote(String.reverse(reversed))

def literals(text: String, remaining: Nat, reversed: String, f: File) -> IO(File):
  match text remaining:
    case SNil{} _: write(f, literal(reversed) ++ "\n  ])\n\n")
    case SCon{c, tail} 0n:
      do IO<File>:
        next : File <- write(f, literal(reversed) ++ ",\n")
        literals(tail, 127n, SCon{c, SNil{}}, next)
    case SCon{c, tail} 1n+p: literals(tail, p, SCon{c, reversed}, f)

def module(f: File, +name: String) -> IO(File):
  do IO<File>:
    src : String <- Host.read_text(name ++ ".bend")
    next : File <- write(f, "def " ++ name ++ "() -> String:\n  String.concat([\n")
    literals(src, 128n, "", next)

def embed(path: String) -> IO(Unit):
  do IO<Unit>:
    f : File <- IO.try(File, File.open(path, "w"))
    start : File <- write(f, "import Base\n\n")
    r : File <- module(start, "runtime")
    v : File <- module(r, "message_values")
    g : File <- module(v, "grpc_runtime")
    File.close(g)
