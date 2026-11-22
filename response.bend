import Base
import bend-kit-protobuf@0.2.2.0/protobuf.bend as P

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

def ascii(s: String) -> List<&2, U32>:
  match s:
    case SNil{}: Nil{}
    case SCon{Chr{n}, rest}: Con{n, ascii(rest)}

# Generated filenames are ASCII. An omitted name appends this record to the
# preceding file in the protoc response.
def name_header(name: String) -> List<&2, U32>:
  match name:
    case "": Nil{}
    case s:
      +bytes = ascii(s)
      length = U32.from_nat(List.length(&2, U32, bytes))
      List.append(&2, U32, length_prefix(10, length), bytes)

def chunk(f: File, name: String, content: String, +size: U32) -> IO(File):
  +header = List.append(&2, U32, name_header(name), length_prefix(122, size))
  record_size = U32.add(U32.from_nat(List.length(&2, U32, header)), size)
  do IO<File>:
    next : File <- binary(f, List.append(&2, U32, length_prefix(122, record_size), header))
    utf8(next, content)

def joined(reversed: List<&2, String>) -> String:
  match reversed:
    case [text]: text
    case parts: String.concat(List.reverse(&2, String, parts))

def flush(f: File, name: String, parts: List<&2, String>, size: U32) -> IO(File):
  match name parts:
    case "" Nil{}: IO.pure(File, f)
    case n xs: chunk(f, n, joined(xs), size)

def batch(full: Bool, f: File, name: String, parts: List<&2, String>, size: U32,
          more: File -> String -> List<&2, String> -> U32 -> IO(File)) -> IO(File):
  match full:
    case False{}: more(f, name, parts, size)
    case True{}:
      do IO<File>:
        next : File <- chunk(f, name, joined(parts), size)
        more(next, "", Nil{}, 0)

# Render declarations on demand and batch them to amortize pipe writes.
def chunks(xs: List<(Unit -> String)>, f: File, name: String, parts: List<&2, String>, size: U32) -> IO(File):
  match xs:
    case Nil{}: flush(f, name, parts, size)
    case Con{render, tail}:
      +text = render(Unit{})
      +total = byte_length(text, size)
      batch(U32.is_ge(total, 32768), f, name, Con{text, parts}, total,
        file => n => ps => len => chunks(tail, file, n, ps, len))

def file(f: File, name: String, +text: String) -> IO(File):
  chunk(f, name, text, byte_length(text, 0))

def error(f: File, +msg: String) -> IO(Unit):
  do IO<Unit>:
    a : File <- binary(f, length_prefix(10, byte_length(msg, 0)))
    b : File <- utf8(a, msg)
    File.close(b)
