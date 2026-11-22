import Base
import ../runtime.bend as R

def check(ok: Bool, description: String) -> IO(Unit):
  match ok:
    case True{}: IO.pure(Unit, Unit{})
    case False{}: IO.die(Unit, 1, description)

# 1 (unpacked), 150 and 255 (packed), then 2 (unpacked).
def mixed(fs: Maybe<&2, List<&2, R.Field>>) -> Maybe<&2, List<&2, R.Value>>:
  match fs:
    case None{}: None{}
    case Some{fields}: R.read_many(1, 0, fields)

def mixed_ok(vs: Maybe<&2, List<&2, R.Value>>) -> Bool:
  match vs:
    case Some{[R.Var{0, 1}, R.Var{0, 150}, R.Var{0, 255}, R.Var{0, 2}]}: True{}
    case _: False{}

def wire_ok(bs: Maybe<&2, List<&2, U32>>) -> Bool:
  match bs:
    case Some{[10, 3, 1, 150, 1, 17, 0, 0, 0, 0, 0, 0, 0, 128]}: True{}
    case _: False{}

def scalar_ok(i: Maybe<&2, R.Word64>, f: Maybe<&2, F32>, s: Maybe<&2, String>) -> Bool:
  match i f s:
    case Some{R.Word64{2147483648, 0}} Some{float} Some{text}:
      U32.is_eq(F32.bits(float), 2147483648) && String.eq(text, "λ☔")
    case _ _ _: False{}

def merged_ok(v: Maybe<&2, R.Value>) -> Bool:
  match v:
    case Some{R.Blob{[8, 42, 16, 9]}}: True{}
    case _: False{}

def invalid_value(v: Maybe<&2, R.Value>) -> Bool:
  match v:
    case Some{R.Invalid{}}: True{}
    case _: False{}

def main() -> IO(Unit):
  mixed_wire : List<&2, U32> = [8, 1, 10, 4, 150, 1, 255, 1, 8, 2]
  packed = R.pack(0, [R.Var{0, 1}, R.Var{0, 150}])
  encoded = R.render_checked([R.Field{1, packed}, R.Field{2, R.put_double(R.Word64{2147483648, 0})}])
  merged = R.child(2, [R.Field{2, R.Blob{[8, 42]}}, R.Field{2, R.Blob{[16, 9]}}])
  malformed = R.child(2, [R.Field{2, R.Blob{[8]}}, R.Field{2, R.Blob{[42]}}])
  do IO<Unit>:
    check(mixed_ok(mixed(R.parse(mixed_wire))), "mixed packed and unpacked occurrences lost wire order")
    check(wire_ok(encoded), "packed varints or little-endian -0.0 encoded incorrectly")
    check(scalar_ok(R.get_sint64(R.put_sint64(R.Word64{2147483648, 0})), R.get_float(R.W32{2147483648}), R.get_string(R.put_string("λ☔"))), "sint64, signed zero, or UTF-8 failed")
    check(merged_ok(merged), "singular embedded messages failed to merge")
    check(invalid_value(malformed), "truncated embedded message crossed an occurrence boundary")
    check(Maybe.is_none(&2, List<&2, R.Value>, mixed(R.parse([10, 1, 128]))), "accepted truncated packed varint")
    check(Maybe.is_none(&2, List<&2, R.Field>, R.parse([11, 20])), "accepted mismatched group delimiter")
    check(Maybe.is_none(&2, List<&2, R.Field>, R.parse([256])), "accepted non-byte input")
    check(Maybe.is_none(&2, String, R.get_string(R.Blob{[237, 160, 128]})), "accepted UTF-8 encoding of surrogate")
    check(invalid_value(R.last_string(1, [R.Field{1, R.Blob{[255]}}, R.Field{1, R.Blob{[65]}}])), "ignored malformed UTF-8 in overwritten string")
    check(Maybe.is_none(&2, List<&2, U32>, R.render_checked([R.Field{1, R.Blob{[256]}}])), "encoded byte outside [0,255]")
