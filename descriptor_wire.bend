# Accessors for the descriptor and compiler plugin protocol. Field numbers are
# defined in google/protobuf/descriptor.proto and compiler/plugin.proto.
import Base
import ./runtime.bend as R
import bend-kit-protobuf@0.2.2.0/protobuf.bend as P

def Doc() -> Data:
  List<&2, R.Field>

def Checked(-A: Data) -> Data:
  Result<&2, &2, String, A>

# Keep large ignored fields in the codec's byte-buffer representation. Only
# retained descriptor payloads are expanded into Bend lists.
def selected(wanted: Bool, number: U32, value: P.Value, rest: Doc) -> Doc:
  match wanted:
    case True{}: Con{R.Field{number, R.from_wire(value)}, rest}
    case False{}: rest

def select_fields(~keep: U32 -> Bool, xs: List<&1, P.Field>, rev: Doc) -> Doc:
  match xs:
    case Nil{}: List.reverse(&2, R.Field, rev)
    case Con{P.Field{+n, value}, tail}:
      select_fields(~keep, tail, selected(keep(n), n, value, rev))

def select_decoded(~keep: U32 -> Bool, decoded: Result<&2, &1, P.Error, List<&1, P.Field>>) -> Maybe<&2, Doc>:
  match decoded:
    case Fail{e}: None{}
    case Done{fs}: Some{select_fields(~keep, fs, Nil{})}

def parsed(x: Maybe<&2, Doc>) -> Checked(Doc):
  match x:
    case None{}: Fail{"Malformed protobuf descriptor"}
    case Some{v}: Done{v}

def object(v: R.Value) -> Checked(Doc):
  match v:
    case R.Blob{bytes}: parsed(R.parse(bytes))
    case _: Fail{"Expected a length-delimited descriptor"}

# FileDescriptorProto metadata such as SourceCodeInfo can be larger than the
# declarations. Keep the tags used to build the schema.
def file_tag(n: U32) -> Bool:
  match n:
    case 1: True{}
    case 2: True{}
    case 4: True{}
    case 5: True{}
    case 6: True{}
    case 12: True{}
    case _: False{}

def file_object(v: R.Value) -> Checked(Doc):
  match v:
    case R.Blob{xs}: parsed(select_decoded(~file_tag, P.decode(R.to_buffer(xs), 2147483647, 100n)))
    case _: Fail{"Expected a length-delimited file descriptor"}

def values_go(doc: Doc, +tag: U32, rev: List<&2, R.Value>) -> List<&2, R.Value>:
  match doc:
    case Nil{}: List.reverse(&2, R.Value, rev)
    case Con{R.Field{num, v}, tail}:
      values_go(tail, tag, List.filter.put(R.Value, v, rev, U32.is_eq(num, tag)))

def values(tag: U32, doc: Doc) -> List<&2, R.Value>:
  values_go(doc, tag, Nil{})

def found(-A: Data, v: Maybe<&2, A>, err: String) -> Checked(A):
  match v:
    case Some{x}: Done{x}
    case None{}: Fail{err}

def text_value(v: R.Value) -> Checked(String):
  found(String, R.get_string(v), "Expected a UTF-8 string in descriptor")

def text_at(v: Maybe<&2, R.Value>) -> Checked(String):
  match v:
    case None{}: Done{""}
    case Some{x}: text_value(x)

def text(doc: Doc, tag: U32) -> Checked(String):
  text_at(R.last_string(tag, doc))

def uint(v: R.Value) -> Checked(U32):
  match v:
    case R.Var{hi, lo}: Done{lo}
    case _: Fail{"Expected a varint in descriptor"}

def number_at(v: Maybe<&2, R.Value>, fallback: U32) -> Checked(U32):
  match v:
    case None{}: Done{fallback}
    case Some{x}: uint(x)

def number(doc: Doc, tag: U32, fallback: U32) -> Checked(U32):
  number_at(R.last(tag, 0, doc), fallback)

def maybe_number_at(v: Maybe<&2, R.Value>) -> Checked(Maybe<&2, U32>):
  match v:
    case None{}: Done{None{}}
    case Some{x}:
      do Result<&2, &2, String, Maybe<&2, U32>>:
        i : U32 <- uint(x)
        return Some{i}

def sub_at(v: Maybe<&2, R.Value>) -> Checked(Doc):
  match v:
    case None{}: Done{Nil{}}
    case Some{x}: object(x)

def sub(doc: Doc, tag: U32) -> Checked(Doc):
  sub_at(R.child(tag, doc))

def many_go(~C: Data, ~A: Data, ~parse: C -> R.Value -> Checked(A), xs: List<&2, R.Value>, +context: C, rev: List<&2, A>) -> Checked(List<&2, A>):
  match xs:
    case Nil{}: Done{List.reverse(&2, A, rev)}
    case Con{v, rest}:
      do Result<&2, &2, String, List<&2, A>>:
        x : A <- parse(context, v)
        many_go(~C, ~A, ~parse, rest, context, Con{x, rev})

def many(~C: Data, ~A: Data, ~parse: C -> R.Value -> Checked(A), xs: List<&2, R.Value>, context: C) -> Checked(List<&2, A>):
  many_go(~C, ~A, ~parse, xs, context, Nil{})

def require(ok: Bool, err: String) -> Checked(Unit):
  match ok:
    case False{}: Fail{err}
    case True{}: Done{Unit{}}

def is_id_tail(s: String) -> Bool:
  match s:
    case SNil{}: True{}
    case SCon{+c, t}: (Char.is_alpha(c) || Char.is_digit(c) || Char.is_eq(c, '_')) && is_id_tail(t)

def is_id(s: String) -> Bool:
  match s:
    case SNil{}: False{}
    case SCon{+c, t}: (Char.is_alpha(c) || Char.is_eq(c, '_')) && is_id_tail(t)

def name(doc: Doc) -> Checked(String):
  do Result<&2, &2, String, String>:
    +s : String <- text(doc, 1)
    ok : Unit <- require(is_id(s), "Missing or invalid descriptor identifier")
    return s

def Checked.pure(-A: Data, x: A) -> Checked(A):
  Done{x}

def Checked.bind(-A: Data, -B: Data, r: Checked(A), f: A -> Checked(B)) -> Checked(B):
  Result.bind(&2, &2, String, A, B, r, f)
