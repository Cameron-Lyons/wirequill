import Base
import bend-kit-protobuf@0.2.2.0/protobuf.bend as P

type Output is Data:
  Output{name: String, content: String}

def byte_length(s: String, acc: U32) -> U32:
  match s:
    case SNil{}: acc
    case SCon{Chr{c}, t}: byte_length(t, U32.add(acc, P.utf8.width(c)))

def varint_go(fuel: Nat, +n: U32, small: Bool) -> List<&2, U32>:
  match fuel small:
    case 0n _: [n]
    case 1n+p True{}: [n]
    case 1n+p False{}:
      +rest = U32.shrn(n, 7n)
      Con{U32.or(128, U32.and(n, 127)), varint_go(p, rest, U32.is_lt(rest, 128))}

def length_prefix(tag: U32, +size: U32) -> List<&2, U32>:
  Con{tag, varint_go(4n, size, U32.is_lt(size, 128))}

def wrote(pair: File & Result<&1, &1, U32 & String, Unit>) -> IO(File):
  (f, outcome) = pair
  do IO<File>:
    u : Unit <- IO.pass(Unit, outcome)
    return f

def binary(f: File, bytes: List<&2, U32>) -> IO(File):
  do IO<File>:
    r : File & Result<&1, &1, U32 & String, Unit> <- File.write_bytes(f, bytes)
    wrote(r)

def utf8(f: File, text: String) -> IO(File):
  do IO<File>:
    r : File & Result<&1, &1, U32 & String, Unit> <- File.write(f, text)
    wrote(r)

# File.write emits UTF-8 directly. Only the tags and lengths need byte lists.
def output(f: File, out: Output) -> IO(File):
  Output{+name, +content} = out
  +n = byte_length(name, 0)
  +c = byte_length(content, 0)
  +name_tag = length_prefix(10, n)
  +text_tag = length_prefix(122, c)
  size = U32.add(U32.add(n, c), U32.from_nat(Nat.add(List.length(&2, U32, name_tag), List.length(&2, U32, text_tag))))
  header = List.append(&2, U32, length_prefix(122, size), name_tag)
  do IO<File>:
    a : File <- binary(f, header)
    b : File <- utf8(a, name)
    d : File <- binary(b, text_tag)
    utf8(d, content)

def files(xs: List<&2, Output>, f: File) -> IO(Unit):
  match xs:
    case Nil{}: File.close(f)
    case Con{x, t}:
      do IO<Unit>:
        next : File <- output(f, x)
        files(t, next)

def write(result: Result<&2, &2, String, List<&2, Output>>, f: File) -> IO(Unit):
  match result:
    case Fail{+msg}:
      do IO<Unit>:
        a : File <- binary(f, length_prefix(10, byte_length(msg, 0)))
        b : File <- utf8(a, msg)
        File.close(b)
    case Done{xs}:
      do IO<Unit>:
        # supported_features = FEATURE_PROTO3_OPTIONAL.
        a : File <- binary(f, [16, 1])
        files(xs, a)
