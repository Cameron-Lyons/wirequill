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

# For message-valued oneof members, only the final uninterrupted run of the
# active member merges. Unrelated fields and mismatched wire types are ignored.
type Member is Data:
  Member{number: U32, wire: U32}

def belongs(xs: List<&2, Member>, +n: U32, +v: R.Value) -> Bool:
  match xs:
    case Nil{}: False{}
    case Con{Member{i, w}, t}: (U32.is_eq(i, n) && R.matches(w, v)) || belongs(t, n, v)

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

def select(fs: List<&2, R.Field>, +members: List<&2, Member>, +state: Choice) -> Choice:
  match fs:
    case Nil{}:
      Choice{n, acc, discarded} = state
      Choice{n, List.reverse(&2, R.Field, acc), discarded}
    case Con{R.Field{+n, +v}, t}:
      Choice{i, _, _} = state
      select(t, members, select_step(belongs(members, n, v), U32.is_eq(n, i), n, v, state))
