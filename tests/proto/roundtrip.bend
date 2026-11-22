import Base
import ./schema.bend as S
import ./runtime.bend as R

# Match protoc's input as typed data, update its optional count, and re-encode.
def update(value: Maybe<&2, S.PB_sample_Item>) -> Maybe<&2, List<&2, U32>>:
  match value:
    case Some{S.PB_sample_Item{Some{0}, [4294967295, 300], Some{S.PB_sample_types_Label{"café"}}, [0, 255, 120], S.PB_sample_types_State{4294967295}, totals, Some{S.PB_sample_Item_Metadata{4294967295}}, [R.Word64{2147483648, 0}], Some{S.Choice_0_PB_sample_Item_enabled{False{}}}}}:
      S.PB_sample_Item.encode(S.PB_sample_Item{Some{7}, [4294967295, 300], Some{S.PB_sample_types_Label{"café"}}, [0, 255, 120], S.PB_sample_types_State.value_NEGATIVE(), totals, Some{S.PB_sample_Item_Metadata{4294967295}}, [R.Word64{2147483648, 0}], Some{S.Choice_0_PB_sample_Item_enabled{False{}}}})
    case _: None{}

def written(r: File & Result<&1, &1, U32 & String, Unit>) -> IO(Unit):
  (f, ok) = r
  do IO<Unit>:
    File.close(f)
    IO.pass(Unit, ok)

def emit(out: Maybe<&2, List<&2, U32>>) -> IO(Unit):
  match out:
    case None{}: IO.die(Unit, 1, "typed message did not match the protoc fixture")
    case Some{bytes}:
      do IO<Unit>:
        f : File <- IO.try(File, File.open("/dev/stdout", "w"))
        r : File & Result<&1, &1, U32 & String, Unit> <- File.write_bytes(f, bytes)
        written(r)

def received(r: File & Result<&1, &1, U32 & String, List<&2, U32>>) -> IO(Unit):
  (f, data) = r
  do IO<Unit>:
    File.close(f)
    bytes : List<&2, U32> <- IO.pass(List<&2, U32>, data)
    emit(update(S.PB_sample_Item.decode(bytes)))

def main() -> IO(Unit):
  do IO<Unit>:
    f : File <- IO.try(File, File.open("/dev/stdin", "r"))
    r : File & Result<&1, &1, U32 & String, List<&2, U32>> <- File.read_bytes(f, 1024)
    received(r)
