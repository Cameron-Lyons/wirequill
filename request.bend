# The plugin stream includes binary descriptors and, on recent protoc, a
# second copy of requested descriptors carrying source-retention options.
import Base
import bend-kit-bytes@0.3.3.1/bytes.bend as B
import bend-kit-protobuf@0.2.2.0/protobuf.bend as P
import ./runtime.bend as R
import ./descriptor_wire.bend as W

def request_field(n: U32) -> Bool:
  match n:
    case 1: True{}
    case 2: True{}
    case 15: True{}
    case _: False{}

def parsed(r: Maybe<&2, W.Doc>) -> IO(W.Doc):
  match r:
    case None{}: IO.die(W.Doc, 1, "Malformed CodeGeneratorRequest")
    case Some{fields}: IO.pure(W.Doc, fields)

def finish(f: File, buffer: B.Bytes) -> IO(W.Doc):
  do IO<W.Doc>:
    File.close(f)
    parsed(W.select_decoded(~request_field, P.decode(buffer, 67108864, 100n)))

def received(r: File & Result<&1, &1, U32 & String, List<&2, U32>>, use: File -> B.Bytes -> IO(W.Doc)) -> IO(W.Doc):
  (f, result) = r
  do IO<W.Doc>:
    bytes : List<&2, U32> <- IO.pass(List<&2, U32>, result)
    use(f, R.to_buffer(bytes))

def block(f: File, size: U32, use: File -> B.Bytes -> IO(W.Doc)) -> IO(W.Doc):
  do IO<W.Doc>:
    r : File & Result<&1, &1, U32 & String, List<&2, U32>> <- File.read_bytes(f, size)
    received(r, use)

def at_limit(f: File, buffer: B.Bytes, extra: B.Bytes) -> IO(W.Doc):
  match extra:
    case B.Bytes{0, _}: finish(f, buffer)
    case _:
      do IO<W.Doc>:
        File.close(f)
        IO.die(W.Doc, 1, "CodeGeneratorRequest exceeds 64 MiB")

def append_block(f: File, buffer: B.Bytes, bytes: B.Bytes, more: File -> B.Bytes -> IO(W.Doc)) -> IO(W.Doc):
  match bytes:
    case B.Bytes{65536, data}: more(f, B.append(buffer, B.Bytes{65536, data}))
    case last: finish(f, B.append(buffer, last))

# File.read_bytes fills each block or reaches EOF. Pack blocks immediately
# so the byte list from one read can be freed before starting the next.
def read_blocks(blocks: Nat, f: File, buffer: B.Bytes) -> IO(W.Doc):
  match blocks:
    case 0n: block(f, 1, next => extra => at_limit(next, buffer, extra))
    case 1n+p: block(f, 65536, next => bytes => append_block(next, buffer, bytes, file => buf => read_blocks(p, file, buf)))

def read() -> IO(W.Doc):
  do IO<W.Doc>:
    f : File <- IO.try(File, File.open("/dev/stdin", "r"))
    read_blocks(1024n, f, B.new(0))
