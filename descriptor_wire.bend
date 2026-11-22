# Accessors for the descriptor and compiler plugin protocol. Field numbers are
# defined in google/protobuf/descriptor.proto and compiler/plugin.proto.
import Base
import ./runtime.bend as R

def Doc() -> Data:
  List<&2, R.Field>

def Checked(-A: Data) -> Data:
  Result<&2, &2, String, A>

def parsed(x: Maybe<&2, Doc>) -> Checked(Doc):
  match x:
    case None{}: Fail{"Malformed protobuf descriptor"}
    case Some{v}: Done{v}

def object(v: R.Value) -> Checked(Doc):
  match v:
    case R.Blob{bytes}: parsed(R.parse(bytes))
    case _: Fail{"Expected a length-delimited descriptor"}

def keep(yes: Bool, v: R.Value, rest: List<&2, R.Value>) -> List<&2, R.Value>:
  match yes:
    case True{}: Con{v, rest}
    case False{}: rest

def values(tag: U32, doc: Doc) -> List<&2, R.Value>:
  match doc:
    case Nil{}: Nil{}
    case Con{R.Field{num, v}, tail}:
      +k = tag
      keep(U32.is_eq(num, k), v, values(k, tail))

def first(xs: List<&2, R.Value>) -> Maybe<&2, R.Value>:
  match xs:
    case Nil{}: None{}
    case Con{x, t}: Some{x}

def found(-A: Data, v: Maybe<&2, A>, err: String) -> Checked(A):
  match v:
    case Some{x}: Done{x}
    case None{}: Fail{err}

def text_value(v: R.Value) -> Checked(String):
  found(String, R.get_string(v), "Expected a UTF-8 string in descriptor")

def text_at(xs: List<&2, R.Value>, d: String) -> Checked(String):
  match xs:
    case Nil{}: Done{d}
    case Con{x, t}: text_value(x)

def text(+doc: Doc, tag: U32) -> Checked(String):
  text_at(values(tag, doc), "")

def uint(v: R.Value) -> Checked(U32):
  match v:
    case R.Var{hi, lo}: Done{lo}
    case _: Fail{"Expected a varint in descriptor"}

def number_at(v: Maybe<&2, R.Value>, fallback: U32) -> Checked(U32):
  match v:
    case None{}: Done{fallback}
    case Some{x}: uint(x)

def number(doc: Doc, tag: U32, fallback: U32) -> Checked(U32):
  number_at(first(values(tag, doc)), fallback)

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
  sub_at(first(values(tag, doc)))

def many(~A: Data, ~parse: String -> R.Value -> Checked(A), xs: List<&2, R.Value>, +scope: String) -> Checked(List<&2, A>):
  match xs:
    case Nil{}: Done{Nil{}}
    case Con{v, rest}:
      do Result<&2, &2, String, List<&2, A>>:
        x : A <- parse(scope, v)
        t : List<&2, A> <- many(~A, ~parse, rest, scope)
        return Con{x, t}

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
