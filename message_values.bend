import Base
import ./runtime.bend as R

# A missing field is distinct from a present field with an invalid payload.
def optional(~A: Data, ~get: R.Value -> Maybe<&2, A>, v: Maybe<&2, R.Value>) -> Maybe<&2, Maybe<&2, A>>:
  match v:
    case None{}: Some{None{}}
    case Some{x}: Maybe.map(&2, A, Maybe<&2, A>, y => Some{y}, get(x))

def scalar(~A: Data, ~get: R.Value -> Maybe<&2, A>, v: Maybe<&2, R.Value>, d: A) -> Maybe<&2, A>:
  match v:
    case None{}: Some{d}
    case Some{x}: get(x)

def list(~A: Data, ~get: R.Value -> Maybe<&2, A>, xs: List<&2, R.Value>) -> Maybe<&2, List<&2, A>>:
  match xs:
    case Nil{}: Some{Nil{}}
    case Con{v, t}:
      do Maybe<&2, List<&2, A>>:
        h : A <- get(v)
        rest : List<&2, A> <- list(~A, ~get, t)
        return Con{h, rest}

def many(~A: Data, ~get: R.Value -> Maybe<&2, A>, number: U32, wire: U32, fs: List<&2, R.Field>) -> Maybe<&2, List<&2, A>>:
  do Maybe<&2, List<&2, A>>:
    xs : List<&2, R.Value> <- R.read_many(number, wire, fs)
    list(~A, ~get, xs)

def emit_optional(~A: Data, ~put: A -> R.Value, number: U32, v: Maybe<&2, A>) -> List<&2, R.Field>:
  match v:
    case None{}: Nil{}
    case Some{x}: [R.Field{number, put(x)}]

def emit_unless(empty: Bool, number: U32, value: R.Value) -> List<&2, R.Field>:
  match empty:
    case True{}: Nil{}
    case False{}: [R.Field{number, value}]

def zero(v: R.Value) -> Bool:
  match v:
    case R.Var{hi, lo}: U32.is_zero(hi) && U32.is_zero(lo)
    case R.W32{bits}: U32.is_zero(bits)
    case R.W64{hi, lo}: U32.is_zero(hi) && U32.is_zero(lo)
    case R.Blob{Nil{}}: True{}
    case _: False{}

def emit_scalar(number: U32, +value: R.Value) -> List<&2, R.Field>:
  emit_unless(zero(value), number, value)

def unpacked(~A: Data, ~put: A -> R.Value, +number: U32, xs: List<&2, A>) -> List<&2, R.Field>:
  match xs:
    case Nil{}: Nil{}
    case Con{h, t}: Con{R.Field{number, put(h)}, unpacked(~A, ~put, number, t)}

def values(~A: Data, ~put: A -> R.Value, xs: List<&2, A>) -> List<&2, R.Value>:
  match xs:
    case Nil{}: Nil{}
    case Con{h, t}: Con{put(h), values(~A, ~put, t)}

def packed(~A: Data, ~put: A -> R.Value, number: U32, wire: U32, xs: List<&2, A>) -> List<&2, R.Field>:
  match xs:
    case Nil{}: Nil{}
    case Con{h, t}: [R.Field{number, R.pack(wire, Con{put(h), values(~A, ~put, t)})}]

def to_map(~A: Data, ~key: A -> String, xs: List<&2, A>, acc: Map<&2, A>) -> Map<&2, A>:
  match xs:
    case Nil{}: acc
    case Con{+entry, rest}:
      to_map(~A, ~key, rest, Map.set(&2, A, acc, key(entry), entry))

def word_key(w: R.Word64) -> String:
  R.Word64{hi, lo} = w
  U32.show(hi) ++ "/" ++ U32.show(lo)

def blob(b: Maybe<&2, List<&2, U32>>) -> R.Value:
  match b:
    case None{}: R.Invalid{}
    case Some{bs}: R.Blob{bs}

def checked(ok: Bool) -> Maybe<&2, Unit>:
  match ok:
    case False{}: None{}
    case True{}: Some{Unit{}}

# For message-valued oneof members, only the final uninterrupted run of the
# active member merges. Unrelated fields and mismatched wire types are ignored.
type Choice is Data:
  Choice{number: U32, fields: List<&2, R.Field>, discarded: List<&2, R.Field>}

def select_step(hit: Bool, same: Bool, +n: U32, v: R.Value, state: Choice) -> Choice:
  match hit same:
    case False{} _: state
    case True{} False{}:
      Choice{_, previous, discarded} = state
      Choice{n, [R.Field{n, v}], List.append(&2, R.Field, previous, discarded)}
    case True{} True{}:
      Choice{_, acc, discarded} = state
      Choice{n, Con{R.Field{n, v}, acc}, discarded}

def select_known(fs: List<&2, R.Field>, +state: Choice) -> Choice:
  match fs:
    case Nil{}:
      Choice{n, acc, discarded} = state
      Choice{n, List.reverse(&2, R.Field, acc), discarded}
    case Con{R.Field{+n, +v}, t}:
      Choice{i, _, _} = state
      select_known(t, select_step(True{}, U32.is_eq(n, i), n, v, state))

# Schemas generated before indexed decoding supplied the member list at
# selection time. They may share this module with newly generated schemas.
type Member is Data:
  Member{number: U32, wire: U32}

def belongs(xs: List<&2, Member>, +n: U32, +v: R.Value) -> Bool:
  match xs:
    case Nil{}: False{}
    case Con{Member{i, w}, t}: (U32.is_eq(i, n) && R.matches(w, v)) || belongs(t, n, v)

def select(fs: List<&2, R.Field>, +members: List<&2, Member>, +state: Choice) -> Choice:
  match fs:
    case Nil{}: select_known(Nil{}, state)
    case Con{R.Field{+n, +v}, t}:
      Choice{i, _, _} = state
      select(t, members, select_step(belongs(members, n, v), U32.is_eq(n, i), n, v, state))

# Repeated numeric values may be packed. For strings, bytes, and messages
# the ordinary wire type is already length-delimited.
def repeated_wire(normal: U32, +wire: U32) -> Bool:
  U32.is_eq(wire, normal) || U32.is_eq(wire, 2)

# The generated classifier assigns each declared field or oneof a numeric
# bucket. Key zero collects unknowns in schemas generated with preserve_unknown.
# Descend by low key bits so ordinary low field numbers need only a few nodes.
type FieldIndex is Data:
  EmptyIndex{}
  FieldNode{here: List<&2, R.Field>, even: FieldIndex, odd: FieldIndex}

def branches(index: FieldIndex) -> List<&2, R.Field> & (FieldIndex & FieldIndex):
  match index:
    case EmptyIndex{}: (Nil{}, (EmptyIndex{}, EmptyIndex{}))
    case FieldNode{fs, even, odd}: (fs, (even, odd))

# Each step shifts one bit out of a U32. The zero-fuel case has key zero.
def even_key(key: U32) -> Bool:
  U32.is_zero(U32.and(key, 1))

def index_put(fuel: Nat, key: U32, even_key_bit: Bool, field: R.Field, node: List<&2, R.Field> & (FieldIndex & FieldIndex)) -> FieldIndex:
  match fuel key even_key_bit node:
    case _ 0 _ Tuple{here, Tuple{even, odd}}: FieldNode{Con{field, here}, even, odd}
    case 0n _ _ Tuple{here, Tuple{even, odd}}: FieldNode{here, even, odd}
    case 1n+p k True{} Tuple{here, Tuple{even, odd}}:
      +next = U32.shr(k)
      FieldNode{here, index_put(p, next, even_key(next), field, branches(even)), odd}
    case 1n+p k False{} Tuple{here, Tuple{even, odd}}:
      +next = U32.shr(k)
      FieldNode{here, even, index_put(p, next, even_key(next), field, branches(odd))}

def index_step(key: U32, keep_unknown: Bool, f: R.Field, index: FieldIndex) -> FieldIndex:
  match key keep_unknown:
    case 0 False{}: index
    case +k _: index_put(32n, k, even_key(k), f, branches(index))

def index_go(~route: U32 -> U32 -> U32, +keep_unknown: Bool, fs: List<&2, R.Field>, index: FieldIndex) -> FieldIndex:
  match fs:
    case Nil{}: index
    case Con{R.Field{+n, +v}, rest}:
      index_go(~route, keep_unknown, rest, index_step(route(n, R.wire_kind(v)), keep_unknown, R.Field{n, v}, index))

def index(~route: U32 -> U32 -> U32, keep_unknown: Bool, fs: List<&2, R.Field>) -> FieldIndex:
  index_go(~route, keep_unknown, List.reverse(&2, R.Field, fs), EmptyIndex{})

def bucket_go(index: FieldIndex, key: U32, even_key_bit: Bool) -> List<&2, R.Field>:
  match index key even_key_bit:
    case EmptyIndex{} _ _: Nil{}
    case FieldNode{fs, _, _} 0 _: fs
    case FieldNode{_, even, odd} k True{}:
      +next = U32.shr(k)
      bucket_go(even, next, even_key(next))
    case FieldNode{_, even, odd} k False{}:
      +next = U32.shr(k)
      bucket_go(odd, next, even_key(next))

def bucket(index: FieldIndex, +key: U32) -> List<&2, R.Field>:
  bucket_go(index, key, even_key(key))
