# Adapter between bend-kit’s wire codec and the byte lists used by Bend gRPC.
import Base
import bend-kit-bytes@0.3.3.1/bytes.bend as B
import bend-kit-protobuf@0.2.2.0/protobuf.bend as P

type Word64 is Data:
  Word64{hi: U32, lo: U32}

type Value is Data:
  Var{hi: U32, lo: U32}
  W64{hi: U32, lo: U32}
  Blob{bytes: List<&2, U32>}
  Group{fields: List<&2, Field>}
  W32{bits: U32}
  Invalid{}

type Field is Data:
  Field{number: U32, value: Value}

def valid_bytes(xs: List<&2, U32>) -> Bool:
  match xs:
    case Nil{}: True{}
    case Con{h, t}: U32.is_le(h, 255) && valid_bytes(t)

# bend-kit stores four little-endian bytes per word. Mask each input byte
# as B.set does and leave unused bytes of the final word zero.
def pack_word(a: U32, b: U32, c: U32, d: U32) -> U32:
  ((a .&. 255) .|. ((b .&. 255) << 8n) .|. ((c .&. 255) << 16n) .|. (d << 24n) : U32)

def fill_words(xs: List<&2, U32>, +index: U32, buf: Array<U32>) -> Array<U32>:
  match xs:
    case Nil{}: buf
    case [a]: Array.set(U32, buf, index, pack_word(a, 0, 0, 0))
    case [a, b]: Array.set(U32, buf, index, pack_word(a, b, 0, 0))
    case [a, b, c]: Array.set(U32, buf, index, pack_word(a, b, c, 0))
    case a <> b <> c <> d <> rest:
      fill_words(rest, U32.add(index, 1), Array.set(U32, buf, index, pack_word(a, b, c, d)))

def to_buffer(+xs: List<&2, U32>) -> B.Bytes:
  +n = U32.from_nat(List.length(&2, U32, xs))
  B.Bytes{n, fill_words(xs, 0, B.alloc(n))}

def prepend_lanes(count: U32, a: U32, b: U32, c: U32, d: U32, rest: List<&2, U32>) -> List<&2, U32>:
  match count:
    case 1: a <> rest
    case 2: a <> b <> rest
    case 3: a <> b <> c <> rest
    case _: a <> b <> c <> d <> rest

def prepend_bytes(count: U32, +w: U32, rest: List<&2, U32>) -> List<&2, U32>:
  a = (w .&. 255 : U32)
  b = ((w >> 8n) .&. 255 : U32)
  c = ((w >> 16n) .&. 255 : U32)
  d = (w >> 24n : U32)
  prepend_lanes(count, a, b, c, d, rest)

# Read backwards so prefixing each word directly builds the final wire order.
def drain_words(remaining: Nat, index: U32, count: U32, read: Array<U32> & U32, acc: List<&2, U32>) -> List<&2, U32>:
  match remaining read:
    case 0n Tuple{buf, word}: prepend_bytes(count, word, acc)
    case 1n+p Tuple{buf, word}:
      +previous = U32.sub(index, 1)
      drain_words(p, previous, 4, Array.get(U32, buf, previous), prepend_bytes(count, word, acc))

def from_buffer(b: B.Bytes) -> List<&2, U32>:
  match b:
    case B.Bytes{0, _}: Nil{}
    case B.Bytes{n, buf}:
      +last = U32.sub(n, 1)
      +index = U32.shrn(last, 2n)
      count = U32.add(U32.and(last, 3), 1)
      drain_words(U32.to_nat(index), index, count, Array.get(U32, buf, index), Nil{})

# Scalar conversions are also used by the packed-field helpers.
def from_scalar(v: P.Value) -> Value:
  match v:
    case P.Varint{P.Word64{h, l}}: Var{h, l}
    case P.Fixed64{P.Word64{h, l}}: W64{h, l}
    case P.Blob{b}: Blob{from_buffer(b)}
    case P.Group{xs}: Invalid{}
    case P.Fixed32{w}: W32{w}

# The upstream parser caps group depth at 100. The same bound keeps the
# conversions total while preserving the contents of unknown legacy groups.
def from_fields_at(+depth: Nat, xs: List<&1, P.Field>) -> List<&2, Field>:
  match depth xs:
    case d Nil{}: Nil{}
    case 1n+p Con{P.Field{n, P.Group{inner}}, t}:
      Con{Field{n, Group{from_fields_at(p, inner)}}, from_fields_at(depth, t)}
    case d Con{P.Field{n, v}, t}: Con{Field{n, from_scalar(v)}, from_fields_at(depth, t)}

def from_wire(v: P.Value) -> Value:
  match v:
    case P.Group{xs}: Group{from_fields_at(99n, xs)}
    case other: from_scalar(other)

def parsed(r: Result<&2, &1, P.Error, List<&1, P.Field>>) -> Maybe<&2, List<&2, Field>>:
  match r:
    case Fail{e}: None{}
    case Done{xs}: Some{from_fields_at(100n, xs)}

def parse_valid(ok: Bool, xs: List<&2, U32>) -> Maybe<&2, List<&2, Field>>:
  match ok:
    case False{}: None{}
    case True{}: parsed(P.decode(to_buffer(xs), 2147483647, 100n))

def parse(+xs: List<&2, U32>) -> Maybe<&2, List<&2, Field>>:
  parse_valid(valid_bytes(xs), xs)

def wire_blob(ok: Bool, xs: List<&2, U32>) -> Maybe<&1, P.Value>:
  match ok:
    case False{}: None{}
    case True{}: Some{P.Blob{to_buffer(xs)}}

def to_scalar(v: Value) -> Maybe<&1, P.Value>:
  match v:
    case Var{h, l}: Some{P.Varint{P.Word64{h, l}}}
    case W64{h, l}: Some{P.Fixed64{P.Word64{h, l}}}
    case Blob{+xs}: wire_blob(valid_bytes(xs), xs)
    case W32{w}: Some{P.Fixed32{w}}
    case _: None{}

def to_fields_at(+depth: Nat, xs: List<&2, Field>) -> Maybe<&1, List<&1, P.Field>>:
  match depth xs:
    case d Nil{}: Some{Nil{}}
    case 1n+p Con{Field{n, Group{inner}}, t}:
      do Maybe<&1, List<&1, P.Field>>:
        group : List<&1, P.Field> <- to_fields_at(p, inner)
        tail : List<&1, P.Field> <- to_fields_at(depth, t)
        return Con{P.Field{n, P.Group{group}}, tail}
    case d Con{Field{n, v}, t}:
      do Maybe<&1, List<&1, P.Field>>:
        w : P.Value <- to_scalar(v)
        tail : List<&1, P.Field> <- to_fields_at(depth, t)
        return Con{P.Field{n, w}, tail}

def encoded(r: Result<&2, &1, P.Error, B.Bytes>) -> Maybe<&2, List<&2, U32>>:
  match r:
    case Fail{e}: None{}
    case Done{b}: Some{from_buffer(b)}

def render_fields(r: Maybe<&1, List<&1, P.Field>>) -> Maybe<&2, List<&2, U32>>:
  match r:
    case None{}: None{}
    case Some{xs}: encoded(P.encode(xs, 2147483647, 100n))

def render_checked(xs: List<&2, Field>) -> Maybe<&2, List<&2, U32>>:
  render_fields(to_fields_at(100n, xs))

def wire_kind(v: Value) -> U32:
  match v:
    case Var{h, l}: 0
    case W64{h, l}: 1
    case Blob{b}: 2
    case Group{fs}: 3
    case W32{w}: 5
    case Invalid{}: 7

def matches(kind: U32, v: Value) -> Bool:
  U32.is_eq(kind, wire_kind(v))

def last_go(xs: List<&2, Field>, +number: U32, +kind: U32, acc: Maybe<&2, Value>) -> Maybe<&2, Value>:
  match xs:
    case Nil{}: acc
    case Con{Field{n, +v}, t}:
      ok = U32.is_eq(n, number) && matches(kind, v)
      next = Bool.pick(Maybe<&2, Value>, ok, Some{v}, acc)
      last_go(t, number, kind, next)

def last(number: U32, kind: U32, fields: List<&2, Field>) -> Maybe<&2, Value>:
  last_go(fields, number, kind, None{})

def from_values(xs: List<&1, P.Value>) -> List<&2, Value>:
  match xs:
    case Nil{}: Nil{}
    case Con{h, t}: Con{from_wire(h), from_values(t)}

def unpacked(r: Result<&2, &1, P.Error, List<&1, P.Value>>) -> Maybe<&2, List<&2, Value>>:
  match r:
    case Fail{e}: None{}
    case Done{vs}: Some{from_values(vs)}

# A repeated numeric field accepts interleaved packed and unpacked occurrences.
def read_occurrence(same: Bool, direct: Bool, kind: U32, v: Value) -> Maybe<&2, List<&2, Value>>:
  match same direct:
    case False{} _: Some{Nil{}}
    case True{} True{}: Some{[v]}
    case True{} False{}:
      match v:
        case Blob{xs}: unpacked(P.packed_decode(kind, to_buffer(xs), 2147483647))
        case _: Some{Nil{}}

def read_many_go(xs: List<&2, Field>, +number: U32, +kind: U32, acc: List<&2, Value>) -> Maybe<&2, List<&2, Value>>:
  match xs:
    case Nil{}: Some{List.reverse(&2, Value, acc)}
    case Con{Field{n, +v}, t}:
      do Maybe<&2, List<&2, Value>>:
        vs : List<&2, Value> <- read_occurrence(U32.is_eq(n, number), matches(kind, v), kind, v)
        read_many_go(t, number, kind, List.reverse.go(&2, Value, vs, acc))

def read_many(number: U32, kind: U32, fields: List<&2, Field>) -> Maybe<&2, List<&2, Value>>:
  read_many_go(fields, number, kind, Nil{})

def packed_wire(ok: Bool, v: Value) -> Maybe<&1, P.Value>:
  match ok:
    case False{}: None{}
    case True{}: to_scalar(v)

def to_packed(xs: List<&2, Value>, +kind: U32) -> Maybe<&1, List<&1, P.Value>>:
  match xs:
    case Nil{}: Some{Nil{}}
    case Con{+v, t}:
      do Maybe<&1, List<&1, P.Value>>:
        w : P.Value <- packed_wire(matches(kind, v), v)
        tail : List<&1, P.Value> <- to_packed(t, kind)
        return Con{w, tail}

def packed_bytes(r: Result<&2, &1, P.Error, B.Bytes>) -> Value:
  match r:
    case Fail{e}: Invalid{}
    case Done{b}: Blob{from_buffer(b)}

def packed(r: Maybe<&1, List<&1, P.Value>>) -> Value:
  match r:
    case None{}: Invalid{}
    case Some{vs}: packed_bytes(P.packed_encode(vs, 2147483647))

def pack(kind: U32, values: List<&2, Value>) -> Value:
  packed(to_packed(values, kind))

# A singular embedded message merges occurrences, equivalent to decoding their
# concatenated contents. Validate each boundary first so that a truncated
# occurrence cannot consume bytes from the following occurrence.
def valid_message(r: Result<&2, &1, P.Error, List<&1, P.Field>>) -> Bool:
  match r:
    case Fail{e}: False{}
    case Done{fs}: True{}

def child_checked(ok: Bool, next: Unit -> Value) -> Value:
  match ok:
    case False{}: Invalid{}
    case True{}: next(Unit{})

def join_child(vs: List<&2, Value>, acc: List<&2, U32>) -> Value:
  match vs:
    case Nil{}: Blob{List.reverse(&2, U32, acc)}
    case Con{Blob{+xs}, t}:
      ok = valid_message(P.decode(to_buffer(xs), 2147483647, 100n))
      next = List.reverse.go(&2, U32, xs, acc)
      child_checked(ok, u => join_child(t, next))
    case Con{v, t}: Invalid{}

def child_parts(r: Maybe<&2, List<&2, Value>>) -> Maybe<&2, Value>:
  match r:
    case None{}: Some{Invalid{}}
    case Some{vs}:
      match vs:
        case Nil{}: None{}
        case Con{v, Nil{}}: Some{v}
        case Con{v, t}: Some{join_child(Con{v, t}, Nil{})}

def child(number: U32, fields: List<&2, Field>) -> Maybe<&2, Value>:
  child_parts(read_many(number, 2, fields))

def get_bytes(v: Value) -> Maybe<&2, List<&2, U32>>:
  match v:
    case Blob{xs}: Some{xs}
    case _: None{}

def put_bytes(xs: List<&2, U32>) -> Value:
  Blob{xs}

def got_string(r: Result<&2, &2, P.Error, String>) -> Maybe<&2, String>:
  match r:
    case Fail{e}: None{}
    case Done{s}: Some{s}

def read_string_bytes(ok: Bool, xs: List<&2, U32>) -> Maybe<&2, String>:
  match ok:
    case False{}: None{}
    case True{}: got_string(P.to_string(P.Blob{to_buffer(xs)}))

def get_string(v: Value) -> Maybe<&2, String>:
  match v:
    case Blob{+xs}: read_string_bytes(valid_bytes(xs), xs)
    case _: None{}

# Strings must be valid UTF-8 even if another singular occurrence overwrites
# them. The ordinary typed getter will validate the final occurrence.
def replace_string(yes: Bool, prev: Maybe<&2, Value>, next: Value) -> Maybe<&2, Value>:
  match yes prev:
    case False{} old: old
    case True{} None{}: Some{next}
    case True{} Some{v}:
      Some{Bool.pick(Value, Maybe.is_some(&2, String, get_string(v)), next, Invalid{})}

def last_string_go(xs: List<&2, Field>, +number: U32, prev: Maybe<&2, Value>) -> Maybe<&2, Value>:
  match xs:
    case Nil{}: prev
    case Con{Field{n, +v}, t}:
      yes = U32.is_eq(number, n) && matches(2, v)
      last_string_go(t, number, replace_string(yes, prev, v))

def last_string(number: U32, fields: List<&2, Field>) -> Maybe<&2, Value>:
  last_string_go(fields, number, None{})

def string_value(r: Result<&2, &1, P.Error, P.Value>) -> Value:
  match r:
    case Fail{e}: Invalid{}
    case Done{v}: from_wire(v)

def put_string(s: String) -> Value:
  string_value(P.from_string(s))

# Protobuf's 32-bit scalar conversions truncate varints to their low 32 bits.
def get_uint32(v: Value) -> Maybe<&2, U32>:
  match v:
    case Var{h, l}: Some{l}
    case _: None{}

def put_uint32(n: U32) -> Value:
  Var{0, n}

def get_int32(v: Value) -> Maybe<&2, U32>:
  get_uint32(v)

def put_int32(n: U32) -> Value:
  from_wire(P.from_int32(n))

def get_sint32(v: Value) -> Maybe<&2, U32>:
  Maybe.map(&2, U32, U32, x => P.unzigzag32(x), get_uint32(v))

def put_sint32(n: U32) -> Value:
  from_wire(P.from_sint32(n))

def get_fixed32(v: Value) -> Maybe<&2, U32>:
  match v:
    case W32{w}: Some{w}
    case _: None{}

def put_fixed32(n: U32) -> Value:
  W32{n}

def get_sfixed32(v: Value) -> Maybe<&2, U32>:
  get_fixed32(v)

def put_sfixed32(n: U32) -> Value:
  put_fixed32(n)

def get_uint64(v: Value) -> Maybe<&2, Word64>:
  match v:
    case Var{h, l}: Some{Word64{h, l}}
    case _: None{}

def put_uint64(n: Word64) -> Value:
  Word64{h, l} = n
  Var{h, l}

def get_int64(v: Value) -> Maybe<&2, Word64>:
  get_uint64(v)

def put_int64(w: Word64) -> Value:
  put_uint64(w)

def word_of(w: P.Word64) -> Word64:
  P.Word64{h, l} = w
  Word64{h, l}

def get_sint64(v: Value) -> Maybe<&2, Word64>:
  match v:
    case Var{h, l}: Some{word_of(P.Word64.unzigzag(P.Word64{h, l}))}
    case _: None{}

def put_sint64(w: Word64) -> Value:
  Word64{h, l} = w
  from_wire(P.from_sint64(P.Word64{h, l}))

def get_fixed64(v: Value) -> Maybe<&2, Word64>:
  match v:
    case W64{h, l}: Some{Word64{h, l}}
    case _: None{}

def put_fixed64(w: Word64) -> Value:
  Word64{h, l} = w
  W64{h, l}

def get_sfixed64(v: Value) -> Maybe<&2, Word64>:
  get_fixed64(v)

def put_sfixed64(w: Word64) -> Value:
  put_fixed64(w)

def get_bool(v: Value) -> Maybe<&2, Bool>:
  match v:
    case Var{h, l}: Some{Bool.not(U32.is_zero(U32.or(h, l)))}
    case _: None{}

def put_bool(b: Bool) -> Value:
  put_uint32(Bool.to_u32(b))

def get_float(v: Value) -> Maybe<&2, F32>:
  Maybe.map(&2, U32, F32, P.float_of_bits, get_fixed32(v))

def put_float(f: F32) -> Value:
  W32{F32.bits(f)}

# Doubles preserve all IEEE-754 payload bits, including signed zero and NaNs.
def get_double(v: Value) -> Maybe<&2, Word64>:
  get_fixed64(v)

def put_double(w: Word64) -> Value:
  put_fixed64(w)
