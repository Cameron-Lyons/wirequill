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
  valid_type && valid_tag && (U32.is_lt(num, 19000) || U32.is_gt(num, 19999)) && (U32.is_eq(label, 1) || U32.is_eq(label, 3))

type FieldScope is Data:
  FieldScope{name: String, groups: U32}

def valid_group(group: Maybe<&2, U32>, count: U32, repeated: Bool, optional: Bool) -> Bool:
  match group:
    case None{}: Bool.not(optional)
    case Some{i}: U32.is_lt(i, count) && Bool.not(repeated)

def field(context: FieldScope, v: R.Value) -> W.Checked(M.Field):
  FieldScope{+scope, count} = context
  do W.Checked<M.Field>:
    +doc : W.Doc <- W.object(v)
    +name : String <- W.name(doc)
    +num : U32 <- W.number(doc, 3, 0)
    +label : U32 <- W.number(doc, 4, 1)
    +kind : U32 <- W.number(doc, 5, 0)
    target : String <- W.text(doc, 6)
    +group : Maybe<&2, U32> <- W.maybe_number_at(R.last(9, 0, doc))
    opt : U32 <- W.number(doc, 17, 0)
    opts : W.Doc <- W.sub(doc, 8)
    packed : U32 <- W.number(opts, 2, 1)
    ok : Unit <- W.require(supported_field(kind, num, label), "Unsupported field " ++ scope ++ "." ++ name)
    +optional : Bool = nonzero(opt)
    +repeated : Bool = U32.is_eq(label, 3)
    grouped : Unit <- W.require(valid_group(group, count, repeated, optional), "Invalid oneof membership: " ++ scope ++ "." ++ name)
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
    vs : List<&2, M.EnumValue> <- W.many(~String, ~M.EnumValue, ~enum_value, W.values(2, doc), "")
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
    ms : List<&2, M.Method> <- W.many(~String, ~M.Method, ~method, W.values(2, doc), "")
    return M.Service{scope ++ "." ++ n, ms}

def oneof(scope: String, v: R.Value) -> W.Checked(String):
  do W.Checked<String>:
    doc : W.Doc <- W.object(v)
    W.name(doc)

def has(set: Set(), key: String) -> Bool:
  Pair.snd(Set(), Bool, Set.has(set, key))

def unique_field(duplicate_name: Bool, duplicate_tag: Bool, scope: String, name: String, tag: String) -> W.Checked(Unit):
  match duplicate_name duplicate_tag:
    case True{} _: Fail{"Duplicate field name: " ++ scope ++ "." ++ name}
    case _ True{}: Fail{"Duplicate field number " ++ tag ++ " in " ++ scope}
    case _ _: Done{Unit{}}

def next_group(group: Maybe<&2, U32>, count: U32) -> U32:
  match group:
    case None{}: count
    case Some{i}: U32.max(count, U32.add(i, 1))

# protoc appends one synthetic oneof for every explicitly optional field.
# Check the field identifiers while finding the real oneof prefix. Field.optional
# already represents presence for the trailing synthetic declarations.
def check_fields(xs: List<&2, M.Field>, +scope: String, +names: Set(), +tags: Set(), groups: U32) -> W.Checked(U32):
  match xs:
    case Nil{}: Done{groups}
    case Con{M.Field{+name, number, _, _, _, _, group, _}, t}:
      +tag = U32.show(number)
      do W.Checked<U32>:
        ok : Unit <- unique_field(has(names, name), has(tags, tag), scope, name, tag)
        check_fields(t, scope, Set.add(names, name), Set.add(tags, tag), next_group(group, groups))

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
        +groups : List<&2, String> <- W.many(~String, ~String, ~oneof, W.values(8, doc), "")
        context : FieldScope = FieldScope{full, U32.from_nat(List.length(&2, String, groups))}
        +fields : List<&2, M.Field> <- W.many(~FieldScope, ~M.Field, ~field, W.values(2, doc), context)
        count : U32 <- check_fields(fields, full, Set.new(), Set.new(), 0)
        real_groups : List<&2, String> = List.take(&2, String, groups, U32.to_nat(count))
        opts : W.Doc <- W.sub(doc, 7)
        map : U32 <- W.number(opts, 7, 0)
        es : List<&2, M.Enum> <- W.many(~String, ~M.Enum, ~enum_decl, W.values(4, doc), full)
        nested : Schema <- messages(d, W.values(3, doc), full)
        rest : Schema <- messages(depth, tail, scope)
        return join(Schema{[M.Message{full, fields, real_groups, nonzero(map)}], es, Nil{}}, join(nested, rest))

def valid_package(pkg: String) -> Bool:
  match pkg:
    case SNil{}: True{}
    case SCon{h, t}: List.all(~&2, ~String, ~W.is_id, String.split(SCon{h, t}, '.'))

def prefix(pkg: String) -> String:
  match pkg:
    case SNil{}: ""
    case SCon{h, t}: SCon{Chr{46}, SCon{h, t}}

type FileSchema is Data:
  FileSchema{path: String, schema: Schema}

# Files used to declare custom options often import descriptor.proto. Their
# proto2 or Editions message semantics only matter if a generated type uses
# them. Reference validation below checks that distinction after pooling files.
def file_body(syntax: String, +requested: Bool, +doc: W.Doc, path: String) -> W.Checked(Schema):
  match syntax requested:
    case "proto3" root:
      do W.Checked<Schema>:
        +pkg : String <- W.text(doc, 2)
        valid : Unit <- W.require(valid_package(pkg), "Invalid protobuf package in " ++ path)
        +scope : String = prefix(pkg)
        body : Schema <- messages(128n, W.values(4, doc), scope)
        es : List<&2, M.Enum> <- W.many(~String, ~M.Enum, ~enum_decl, W.values(5, doc), scope)
        declarations : List<&2, R.Value> = Bool.pick(List<&2, R.Value>, root, W.values(6, doc), Nil{})
        ss : List<&2, M.Service> <- W.many(~String, ~M.Service, ~service, declarations, scope)
        return join(body, Schema{Nil{}, es, ss})
    case _ True{}: Fail{"Only proto3 schemas are supported as roots: " ++ path}
    case "" False{}: Done{empty()}
    case "proto2" False{}: Done{empty()}
    case "editions" False{}: Done{empty()}
    case _ False{}: Fail{"Unknown protobuf syntax in " ++ path}

def file(roots: Set(), v: R.Value) -> W.Checked(FileSchema):
  do W.Checked<FileSchema>:
    +doc : W.Doc <- W.file_object(v)
    +path : String <- W.text(doc, 1)
    valid : Unit <- W.require(Bool.not(String.is_empty(path)), "Missing file descriptor name")
    syntax : String <- W.text(doc, 12)
    schema : Schema <- file_body(syntax, has(roots, path), doc, path)
    return FileSchema{path, schema}

def pool(xs: List<&2, FileSchema>) -> Schema:
  match xs:
    case Nil{}: empty()
    case Con{FileSchema{p, s}, rest}: join(s, pool(rest))

def file_paths(xs: List<&2, FileSchema>, +acc: Set()) -> W.Checked(Set()):
  match xs:
    case Nil{}: Done{acc}
    case Con{FileSchema{+path, _}, t}:
      do W.Checked<Set()>:
        ok : Unit <- W.require(Bool.not(has(acc, path)), "Duplicate file descriptor: " ++ path)
        file_paths(t, Set.add(acc, path))

def check_roots(xs: List<&2, String>, +files: Set()) -> W.Checked(Unit):
  match xs:
    case Nil{}: Done{Unit{}}
    case Con{+h, t}:
      do W.Checked<Unit>:
        ok : Unit <- W.require(has(files, h), "Missing file descriptor: " ++ h)
        check_roots(t, files)

def message_name(m: M.Message) -> String:
  M.Message{name, _, _, _} = m
  name

def enum_name(e: M.Enum) -> String:
  M.Enum{name, _} = e
  name

def service_name(s: M.Service) -> String:
  M.Service{name, _} = s
  name

def symbols(~A: Data, ~name: A -> String, xs: List<&2, A>, +kind: U32, +acc: Map<&2, U32>) -> W.Checked(Map<&2, U32>):
  match xs:
    case Nil{}: Done{acc}
    case Con{x, t}:
      +key = name(x)
      exists = Pair.snd(Map<&2, U32>, Bool, Map.has(&2, U32, acc, key))
      do W.Checked<Map<&2, U32>>:
        ok : Unit <- W.require(Bool.not(exists), "Duplicate protobuf declaration: " ++ key)
        symbols(~A, ~name, t, kind, Map.set(&2, U32, acc, key, kind))

def reference(types: Map<&2, U32>, +target: String, kind: U32, scope: String) -> W.Checked(Unit):
  actual = Pair.snd(Map<&2, U32>, U32, Map.get(U32, 0, types, target))
  W.require(U32.is_eq(actual, kind), "Expected a declared proto3 type for " ++ scope ++ ": " ++ target)

def field_references(xs: List<&2, M.Field>, +types: Map<&2, U32>, +scope: String) -> W.Checked(Unit):
  match xs:
    case Nil{}: Done{Unit{}}
    case Con{M.Field{name, _, 11, target, _, _, _, _}, t}:
      do W.Checked<Unit>:
        ok : Unit <- reference(types, target, 11, scope ++ "." ++ name)
        field_references(t, types, scope)
    case Con{M.Field{name, _, 14, target, _, _, _, _}, t}:
      do W.Checked<Unit>:
        ok : Unit <- reference(types, target, 14, scope ++ "." ++ name)
        field_references(t, types, scope)
    case Con{_, t}: field_references(t, types, scope)

def message_references(xs: List<&2, M.Message>, +types: Map<&2, U32>) -> W.Checked(Unit):
  match xs:
    case Nil{}: Done{Unit{}}
    case Con{M.Message{n, fs, _, _}, t}:
      do W.Checked<Unit>:
        ok : Unit <- field_references(fs, types, n)
        message_references(t, types)

def method_references(xs: List<&2, M.Method>, +types: Map<&2, U32>, +scope: String) -> W.Checked(Unit):
  match xs:
    case Nil{}: Done{Unit{}}
    case Con{M.Method{name, input, output, _, _}, t}:
      +method = scope ++ "/" ++ name
      do W.Checked<Unit>:
        req : Unit <- reference(types, input, 11, method)
        resp : Unit <- reference(types, output, 11, method)
        method_references(t, types, scope)

def service_references(xs: List<&2, M.Service>, +types: Map<&2, U32>) -> W.Checked(Unit):
  match xs:
    case Nil{}: Done{Unit{}}
    case Con{M.Service{name, ms}, t}:
      do W.Checked<Unit>:
        ok : Unit <- method_references(ms, types, name)
        service_references(t, types)

def resolve(+schema: Schema) -> W.Checked(Schema):
  Schema{+ms, es, +ss} = schema
  do W.Checked<Schema>:
    a : Map<&2, U32> <- symbols(~M.Message, ~message_name, ms, 11, MTip{})
    b : Map<&2, U32> <- symbols(~M.Enum, ~enum_name, es, 14, a)
    +types : Map<&2, U32> <- symbols(~M.Service, ~service_name, ss, 0, b)
    fields : Unit <- message_references(ms, types)
    methods : Unit <- service_references(ss, types)
    return schema

def root_name(context: String, v: R.Value) -> W.Checked(String):
  W.text_value(v)

def nonempty(xs: List<&2, String>) -> Bool:
  match xs:
    case Nil{}: False{}
    case Con{x, t}: True{}

def request(+doc: W.Doc) -> W.Checked(Schema):
  do W.Checked<Schema>:
    +roots : List<&2, String> <- W.many(~String, ~String, ~root_name, W.values(1, doc), "")
    any : Unit <- W.require(nonempty(roots), "No .proto files requested")
    +files : List<&2, FileSchema> <- W.many(~Set(), ~FileSchema, ~file, W.values(15, doc), Set.from_list(roots))
    paths : Set() <- file_paths(files, Set.new())
    found : Unit <- check_roots(roots, paths)
    resolve(pool(files))
