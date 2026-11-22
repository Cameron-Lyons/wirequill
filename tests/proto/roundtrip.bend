import Base
import ./schema.bend as S
import ./runtime.bend as R

# Match protoc's input as typed data, update its optional count, and re-encode.
def update(value: Maybe<&2, S.PB_sample_Item>) -> Maybe<&2, List<&2, U32>>:
  match value:
    case Some{S.PB_sample_Item{Some{0}, [4294967295, 300], Some{S.PB_sample_types_Label{"café"}}, [0, 255, 120], S.PB_sample_types_State{4294967295}, totals, Some{S.PB_sample_Item_Metadata{4294967295}}, [R.Word64{2147483648, 0}], Some{S.Choice_0_PB_sample_Item_enabled{False{}}}}}:
      S.PB_sample_Item.encode(S.PB_sample_Item{Some{7}, [4294967295, 300], Some{S.PB_sample_types_Label{"café"}}, [0, 255, 120], S.PB_sample_types_State.value_NEGATIVE(), totals, Some{S.PB_sample_Item_Metadata{4294967295}}, [R.Word64{2147483648, 0}], Some{S.Choice_0_PB_sample_Item_enabled{False{}}}})
    case _: None{}

def last_map_value(entries: List<&2, S.PB_sample_Item_TotalsEntry>) -> Bool:
  match entries:
    case [S.PB_sample_Item_TotalsEntry{"K", R.Word64{0, 2}}]: True{}
    case _: False{}

# Interleaved packed and unpacked values belong to one repeated field.
# A wrong-wire occurrence cannot switch a oneof or overwrite an optional.
def routed(value: Maybe<&2, S.PB_sample_Item>) -> Bool:
  match value:
    case Some{S.PB_sample_Item{Some{7}, [1, 2, 3], None{}, Nil{}, _, totals, None{}, Nil{}, Some{S.Choice_0_PB_sample_Item_enabled{False{}}}}}:
      last_map_value(Map.values(&2, S.PB_sample_Item_TotalsEntry, totals))
    case _: False{}

def verify(ok: Bool) -> IO(Unit):
  match ok:
    case True{}: IO.pure(Unit, Unit{})
    case False{}: IO.die(Unit, 1, "field indexing changed repeated, map, optional, or oneof values")

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
  wire : List<&2, U32> = [8, 7, 16, 2, 50, 5, 10, 1, 75, 16, 1, 74, 1, 65, 18, 1, 4, 80, 0, 72, 1, 10, 0, 16, 6, 50, 5, 10, 1, 75, 16, 2]
  do IO<Unit>:
    verify(routed(S.PB_sample_Item.decode(wire)))
    f : File <- IO.try(File, File.open("/dev/stdin", "r"))
    r : File & Result<&1, &1, U32 & String, List<&2, U32>> <- File.read_bytes(f, 1024)
    received(r)
