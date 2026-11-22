import Base
import ./descriptor_wire.bend as W
import ./runtime.bend as R
import ./model.bend as M

type Schema is Data:
  Schema{messages: List<&2, M.Message>, enums: List<&2, M.Enum>, services: List<&2, M.Service>}

def empty() -> Schema:
  Schema{Nil{}, Nil{}, Nil{}}

def join(a: Schema, b: Schema) -> Schema:
  Schema{ms, es, ss} = a
  Schema{ns, fs, ts} = b
  Schema{List.append(&2, M.Message, ms, ns), List.append(&2, M.Enum, es, fs), List.append(&2, M.Service, ss, ts)}

def nonzero(n: U32) -> Bool:
  Bool.not(U32.is_zero(n))

def packable(+kind: U32) -> Bool:
  Bool.not(U32.is_eq(kind, 9) || U32.is_eq(kind, 11) || U32.is_eq(kind, 12))

def supported_field(+kind: U32, +num: U32, +label: U32) -> Bool:
  valid_type = U32.is_ge(kind, 1) && U32.is_le(kind, 18) && Bool.not(U32.is_eq(kind, 10))
  valid_tag = U32.is_ge(num, 1) && U32.is_le(num, 536870911)
  valid_type && valid_tag && (U32.is_eq(label, 1) || U32.is_eq(label, 3))

def field(scope: String, v: R.Value) -> W.Checked(M.Field):
  do W.Checked<M.Field>:
    +doc : W.Doc <- W.object(v)
    +name : String <- W.name(doc)
    +num : U32 <- W.number(doc, 3, 0)
    +label : U32 <- W.number(doc, 4, 1)
    +kind : U32 <- W.number(doc, 5, 0)
    target : String <- W.text(doc, 6)
    group : Maybe<&2, U32> <- W.maybe_number_at(W.first(W.values(9, doc)))
    opt : U32 <- W.number(doc, 17, 0)
    opts : W.Doc <- W.sub(doc, 8)
    packed : U32 <- W.number(opts, 2, 1)
    ok : Unit <- W.require(supported_field(kind, num, label), "Unsupported field " ++ scope ++ "." ++ name)
    +optional : Bool = nonzero(opt)
    +repeated : Bool = U32.is_eq(label, 3)
    oneof_index : Maybe<&2, U32> = Bool.pick(Maybe<&2, U32>, optional, None{}, group)
    use_packed : Bool = repeated && packable(kind) && nonzero(packed)
    return M.Field{name, num, kind, target, repeated, optional, oneof_index, use_packed}

def enum_value(scope: String, v: R.Value) -> W.Checked(M.EnumValue):
  do W.Checked<M.EnumValue>:
    +doc : W.Doc <- W.object(v)
    n : String <- W.name(doc)
    i : U32 <- W.number(doc, 2, 0)
    return M.EnumValue{n, i}

def enum_decl(scope: String, v: R.Value) -> W.Checked(M.Enum):
  do W.Checked<M.Enum>:
    +doc : W.Doc <- W.object(v)
    n : String <- W.name(doc)
    vs : List<&2, M.EnumValue> <- W.many(~M.EnumValue, ~enum_value, W.values(2, doc), "")
    return M.Enum{scope ++ "." ++ n, vs}

def method(scope: String, v: R.Value) -> W.Checked(M.Method):
  do W.Checked<M.Method>:
    +doc : W.Doc <- W.object(v)
    n : String <- W.name(doc)
    i : String <- W.text(doc, 2)
    o : String <- W.text(doc, 3)
    c : U32 <- W.number(doc, 5, 0)
    s : U32 <- W.number(doc, 6, 0)
    return M.Method{n, i, o, nonzero(c), nonzero(s)}

def service(scope: String, v: R.Value) -> W.Checked(M.Service):
  do W.Checked<M.Service>:
    +doc : W.Doc <- W.object(v)
    n : String <- W.name(doc)
    ms : List<&2, M.Method> <- W.many(~M.Method, ~method, W.values(2, doc), "")
    return M.Service{scope ++ "." ++ n, ms}

def oneof(scope: String, v: R.Value) -> W.Checked(String):
  do W.Checked<String>:
    doc : W.Doc <- W.object(v)
    W.name(doc)

# Depth bounds the one recursive descriptor type, DescriptorProto.nested_type.
# Siblings use the tail of their descriptor list and consume no nesting depth.
def messages(+depth: Nat, xs: List<&2, R.Value>, +scope: String) -> W.Checked(Schema):
  match depth xs:
    case d Nil{}: Done{empty()}
    case 0n rest: Fail{"Descriptor nesting exceeds 128 messages at " ++ scope}
    case 1n+d Con{v, tail}:
      do W.Checked<Schema>:
        +doc : W.Doc <- W.object(v)
        n : String <- W.name(doc)
        +full : String = scope ++ "." ++ n
        fields : List<&2, M.Field> <- W.many(~M.Field, ~field, W.values(2, doc), full)
        groups : List<&2, String> <- W.many(~String, ~oneof, W.values(8, doc), "")
        opts : W.Doc <- W.sub(doc, 7)
        map : U32 <- W.number(opts, 7, 0)
        es : List<&2, M.Enum> <- W.many(~M.Enum, ~enum_decl, W.values(4, doc), full)
        nested : Schema <- messages(d, W.values(3, doc), full)
        rest : Schema <- messages(depth, tail, scope)
        return join(Schema{[M.Message{full, fields, groups, nonzero(map)}], es, Nil{}}, join(nested, rest))

def contains(xs: List<&2, String>, +s: String) -> Bool:
  match xs:
    case Nil{}: False{}
    case Con{h, t}: String.eq(h, s) || contains(t, s)

def prefix(pkg: String) -> String:
  match pkg:
    case SNil{}: ""
    case SCon{h, t}: SCon{Chr{46}, SCon{h, t}}

type FileSchema is Data:
  FileSchema{path: String, schema: Schema}

def file(v: R.Value, +roots: List<&2, String>) -> W.Checked(FileSchema):
  do W.Checked<FileSchema>:
    +doc : W.Doc <- W.object(v)
    +path : String <- W.text(doc, 1)
    pkg : String <- W.text(doc, 2)
    syntax : String <- W.text(doc, 12)
    ok : Unit <- W.require(String.eq(syntax, "proto3"), "Only proto3 schemas are supported: " ++ path)
    +scope : String = prefix(pkg)
    body : Schema <- messages(128n, W.values(4, doc), scope)
    es : List<&2, M.Enum> <- W.many(~M.Enum, ~enum_decl, W.values(5, doc), scope)
    requested_services : List<&2, R.Value> = Bool.pick(List<&2, R.Value>, contains(roots, path), W.values(6, doc), Nil{})
    ss : List<&2, M.Service> <- W.many(~M.Service, ~service, requested_services, scope)
    return FileSchema{path, join(body, Schema{Nil{}, es, ss})}

def file_list(xs: List<&2, R.Value>, +roots: List<&2, String>) -> W.Checked(List<&2, FileSchema>):
  match xs:
    case Nil{}: Done{Nil{}}
    case Con{h, t}:
      do W.Checked<List<&2, FileSchema>>:
        f : FileSchema <- file(h, roots)
        rest : List<&2, FileSchema> <- file_list(t, roots)
        return Con{f, rest}

def pool(xs: List<&2, FileSchema>) -> Schema:
  match xs:
    case Nil{}: empty()
    case Con{FileSchema{p, s}, rest}: join(s, pool(rest))

def paths(xs: List<&2, FileSchema>) -> List<&2, String>:
  match xs:
    case Nil{}: Nil{}
    case Con{FileSchema{p, s}, rest}: Con{p, paths(rest)}

def check_roots(xs: List<&2, String>, +files: List<&2, String>) -> W.Checked(Unit):
  match xs:
    case Nil{}: Done{Unit{}}
    case Con{+h, t}:
      do W.Checked<Unit>:
        ok : Unit <- W.require(contains(files, h), "Missing file descriptor: " ++ h)
        check_roots(t, files)

def root_name(context: String, v: R.Value) -> W.Checked(String):
  W.text_value(v)

def nonempty(xs: List<&2, String>) -> Bool:
  match xs:
    case Nil{}: False{}
    case Con{x, t}: True{}

def request(+doc: W.Doc) -> W.Checked(Schema):
  do W.Checked<Schema>:
    param : String <- W.text(doc, 2)
    supported : Unit <- W.require(String.is_empty(param), "This plugin accepts no generator parameters")
    +roots : List<&2, String> <- W.many(~String, ~root_name, W.values(1, doc), "")
    any : Unit <- W.require(nonempty(roots), "No .proto files requested")
    +files : List<&2, FileSchema> <- file_list(W.values(15, doc), roots)
    found : Unit <- check_roots(roots, paths(files))
    return pool(files)
