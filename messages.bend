import Base
import ./model.bend as M

# Scalar maps are indexed by FieldDescriptorProto.Type.
def scalar_name(kind: U32) -> String:
  match kind:
    case 1: "double"
    case 2: "float"
    case 3: "int64"
    case 4: "uint64"
    case 5: "int32"
    case 6: "fixed64"
    case 7: "fixed32"
    case 8: "bool"
    case 9: "string"
    case 12: "bytes"
    case 13: "uint32"
    case 15: "sfixed32"
    case 16: "sfixed64"
    case 17: "sint32"
    case 18: "sint64"
    case _: ""

def wire(kind: U32) -> String:
  match kind:
    case 1: "1"
    case 2: "5"
    case 6: "1"
    case 7: "5"
    case 9: "2"
    case 11: "2"
    case 12: "2"
    case 15: "5"
    case 16: "1"
    case _: "0"

def bare(kind: U32, target: String) -> String:
  match kind:
    case 1: "R.Word64"
    case 2: "F32"
    case 3: "R.Word64"
    case 4: "R.Word64"
    case 6: "R.Word64"
    case 8: "Bool"
    case 9: "String"
    case 11: M.name(target)
    case 12: "List<&2, U32>"
    case 14: M.name(target)
    case 16: "R.Word64"
    case 18: "R.Word64"
    case _: "U32"

def default_value(kind: U32, target: String) -> String:
  match kind:
    case 1: "R.Word64{0, 0}"
    case 2: "0.0"
    case 3: "R.Word64{0, 0}"
    case 4: "R.Word64{0, 0}"
    case 6: "R.Word64{0, 0}"
    case 8: "False{}"
    case 9: "\"\""
    case 11: "None{}"
    case 12: "Nil{}"
    case 14: M.name(target) ++ "{0}"
    case 16: "R.Word64{0, 0}"
    case 18: "R.Word64{0, 0}"
    case _: "0"

def convert(+kind: U32, target: String, +verb: String) -> String:
  match kind:
    case 11: M.name(target) ++ "." ++ verb
    case 14: M.name(target) ++ "." ++ verb
    case _: "R." ++ verb ++ "_" ++ scalar_name(kind)

# Slots bind the generated record label, type, default, and wire expressions
# together so their order is identical in the type, encoder, and decoder.
type Slot is Data:
  Slot{label: String, ty: String, zero: String, read: String, write: String, bucket: String}

def field_bucket(num: String) -> String:
  "U32.shln(" ++ num ++ ", 1n)"

def oneof_bucket(i: U32) -> String:
  U32.show(U32.add(U32.shln(i, 1n), 1))

def singular_slot(optional: Bool, +n: String, +ty: String, +num: String, get: String, put: String, lookup: String, +d: String) -> Slot:
  match optional:
    case True{}:
      Slot{n, "Maybe<&2, " ++ ty ++ ">", "None{}", "V.optional(~" ++ ty ++ ", ~" ++ get ++ ", " ++ lookup ++ ")", "V.emit_optional(~" ++ ty ++ ", ~" ++ put ++ ", " ++ num ++ ", " ++ n ++ ")", field_bucket(num)}
    case False{}:
      Slot{n, ty, d, "V.scalar(~" ++ ty ++ ", ~" ++ get ++ ", " ++ lookup ++ ", " ++ d ++ ")", "V.emit_scalar(" ++ num ++ ", " ++ put ++ "(" ++ n ++ "))", field_bucket(num)}

def last_field(kind: U32, num: String, w: String) -> String:
  match kind:
    case 9: "R.last_string(" ++ num ++ ", fs)"
    case _: "R.last(" ++ num ++ ", " ++ w ++ ", fs)"

def scalar_slot(n: String, +num: String, +kind: U32, +target: String, optional: Bool) -> Slot:
  lookup = last_field(kind, num, wire(kind))
  singular_slot(optional, n, bare(kind, target), num, convert(kind, target, "get"), convert(kind, target, "put"), lookup, default_value(kind, target))

def many_write(packed: Bool, +ty: String, put: String, num: String, w: String, value: String) -> String:
  match packed:
    case True{}: "V.packed(~" ++ ty ++ ", ~" ++ put ++ ", " ++ num ++ ", " ++ w ++ ", " ++ value ++ ")"
    case False{}: "V.unpacked(~" ++ ty ++ ", ~" ++ put ++ ", " ++ num ++ ", " ++ value ++ ")"

def repeated_slot(is_map: Bool, +n: String, +num: String, +kind: U32, +target: String, packed: Bool) -> Slot:
  match is_map:
    case True{}:
      +ty = M.name(target)
      read = "Maybe.map(&2, List<&2, " ++ ty ++ ">, Map<&2, " ++ ty ++ ">, xs => V.to_map(~" ++ ty ++ ", ~" ++ ty ++ ".key, xs, MTip{}), V.many(~" ++ ty ++ ", ~" ++ ty ++ ".get, " ++ num ++ ", 2, fs))"
      write = many_write(False{}, ty, ty ++ ".put", num, "2", "Map.values(&2, " ++ ty ++ ", " ++ n ++ ")")
      Slot{n, "Map<&2, " ++ ty ++ ">", "MTip{}", read, write, field_bucket(num)}
    case False{}:
      +ty = bare(kind, target)
      +w = wire(kind)
      read = "V.many(~" ++ ty ++ ", ~" ++ convert(kind, target, "get") ++ ", " ++ num ++ ", " ++ w ++ ", fs)"
      write = many_write(packed, ty, convert(kind, target, "put"), num, w, n)
      Slot{n, "List<&2, " ++ ty ++ ">", "Nil{}", read, write, field_bucket(num)}

def field_slot(repeated: Bool, is_map: Bool, +n: String, +num: String, +kind: U32, +target: String, optional: Bool, packed: Bool) -> Slot:
  match repeated kind:
    case True{} _: repeated_slot(is_map, n, num, kind, target, packed)
    case False{} 11:
      +ty = M.name(target)
      read = "V.optional(~" ++ ty ++ ", ~" ++ ty ++ ".get, R.child(" ++ num ++ ", fs))"
      write = "V.emit_optional(~" ++ ty ++ ", ~" ++ ty ++ ".put, " ++ num ++ ", " ++ n ++ ")"
      Slot{n, "Maybe<&2, " ++ ty ++ ">", "None{}", read, write, field_bucket(num)}
    case False{} k: scalar_slot(n, num, k, target, optional)

def slot_decl(s: Slot) -> String:
  Slot{n, t, _, _, _, _} = s
  n ++ ": " ++ t

def slot_name(s: Slot) -> String:
  Slot{n, _, _, _, _, _} = s
  n

def slot_zero(s: Slot) -> String:
  Slot{_, _, z, _, _, _} = s
  z

def join_slots(~show: Slot -> String, xs: List<&2, Slot>) -> String:
  match xs:
    case Nil{}: ""
    case Con{h, Nil{}}: show(h)
    case Con{h, Con{hh, tt}}: show(h) ++ ", " ++ join_slots(~show, Con{hh, tt})

def read_bucket(indexed: Bool, key: String) -> String:
  match indexed:
    case True{}: "    fs : List<&2, R.Field> = V.bucket(index, " ++ key ++ ")\n"
    case False{}: ""

def reads(xs: List<&2, Slot>, +indexed: Bool) -> String:
  match xs:
    case Nil{}: ""
    case Con{Slot{n, t, _, read, _, key}, rest}:
      read_bucket(indexed, key) ++ "    " ++ n ++ " : " ++ t ++ " <- " ++ read ++ "\n" ++ reads(rest, indexed)

def writes(reversed: List<&2, Slot>) -> String:
  match reversed:
    case Nil{}: ""
    case Con{Slot{_, _, _, _, write, _}, rest}:
      "  out = List.append(&2, R.Field, " ++ write ++ ", out)\n" ++ writes(rest)

def map_set(msgs: List<&2, M.Message>, acc: Set()) -> Set():
  match msgs:
    case Nil{}: acc
    case Con{M.Message{n, _, _, True{}}, t}: map_set(t, Set.add(acc, n))
    case Con{_, t}: map_set(t, acc)

def set_hit(r: Set() & Bool) -> Bool:
  (s, hit) = r
  hit

# Embedded messages normally track presence. A map value instead defaults
# to the empty instance of its declared value type.
def map_value_field(map_entry: Bool, +number: U32, +kind: U32, n: String, +target: String, rep: Bool, entry: Bool, opt: Bool, packed: Bool) -> Slot:
  match map_entry number kind:
    case True{} 2 11:
      +ty = M.name(target)
      +name = "f_" ++ M.ident(n)
      read = "V.scalar(~" ++ ty ++ ", ~" ++ ty ++ ".get, R.child(2, fs), " ++ ty ++ ".default())"
      Slot{name, ty, ty ++ ".default()", read, "[R.Field{2, " ++ ty ++ ".put(" ++ name ++ ")}]", field_bucket("2")}
    case _ _ _: field_slot(rep, entry, "f_" ++ M.ident(n), U32.show(number), kind, target, opt, packed)

def fields(xs: List<&2, M.Field>, +maps: Set(), +map_entry: Bool) -> List<&2, Slot>:
  match xs:
    case Nil{}: Nil{}
    case Con{M.Field{_, _, _, _, _, _, Some{_}, _}, rest}: fields(rest, maps, map_entry)
    case Con{M.Field{n, number, kind, +target, rep, opt, None{}, packed}, rest}:
      entry = set_hit(Set.has(maps, target))
      Con{map_value_field(map_entry, number, kind, n, target, rep, entry, opt, packed), fields(rest, maps, map_entry)}

def group_fields(xs: List<&2, M.Field>, +i: U32) -> List<&2, M.Field>:
  match xs:
    case Nil{}: Nil{}
    case Con{+f, rest}:
      M.Field{_, _, _, _, _, _, g, _} = f
      hit = U32.is_eq(i, Maybe.default(&2, U32, g, 4294967295))
      List.filter.put(M.Field, f, group_fields(rest, i), hit)

def choice_type(n: String, i: U32) -> String:
  "Oneof_" ++ U32.show(i) ++ "_" ++ n

def choice_slot(members: List<&2, M.Field>, +n: String, +name: String, +i: U32, rest: List<&2, Slot>) -> List<&2, Slot>:
  match members:
    case Nil{}: rest
    case Con{_, _}:
      +ty = choice_type(n, i)
      +label = "o_" ++ M.ident(name)
      Con{Slot{label, "Maybe<&2, " ++ ty ++ ">", "None{}", ty ++ ".read(fs)", ty ++ ".write(" ++ label ++ ")", oneof_bucket(i)}, rest}

def choices(gs: List<&2, String>, +n: String, +xs: List<&2, M.Field>, +i: U32) -> List<&2, Slot>:
  match gs:
    case Nil{}: Nil{}
    case Con{g, t}: choice_slot(group_fields(xs, i), n, g, i, choices(t, n, xs, U32.add(i, 1)))

def choice_con(ty: String, f: String) -> String:
  "Choice_" ++ String.drop(ty, 6n) ++ "_" ++ M.ident(f)

def variants(xs: List<&2, M.Field>, +choice: String) -> String:
  match xs:
    case Nil{}: ""
    case Con{M.Field{f, _, k, target, _, _, _, _}, t}:
      "  " ++ choice_con(choice, f) ++ "{value: " ++ bare(k, target) ++ "}\n" ++ variants(t, choice)

def choice_decls(mem: List<&2, M.Field>, +ty: String) -> String:
  match mem:
    case Nil{}: ""
    case Con{h, t}: "type " ++ ty ++ " is Data:\n" ++ variants(Con{h, t}, ty) ++ "\n"

def oneof_decls(gs: List<&2, String>, +n: String, +xs: List<&2, M.Field>, +i: U32) -> String:
  match gs:
    case Nil{}: ""
    case Con{_, t}: choice_decls(group_fields(xs, i), choice_type(n, i)) ++ oneof_decls(t, n, xs, U32.add(i, 1))

def reads_blob(kind: U32, +num: String, w: String) -> String:
  match kind:
    case 11: "R.child(" ++ num ++ ", fs)"
    case k: last_field(k, num, w)

def choice_reads(ms: List<&2, M.Field>, +choice: String) -> String:
  match ms:
    case Nil{}: "    case _: Some{None{}}\n\n"
    case Con{M.Field{f, number, +kind, +target, _, _, _, _}, t}:
      +num = U32.show(number)
      ty = bare(kind, target)
      selected = reads_blob(kind, num, wire(kind))
      # Selected cases have a present, correctly tagged wire value.
      "    case " ++ num ++ ":\n      do Maybe<&2, Maybe<&2, " ++ choice ++ ">>:\n        raw : R.Value <- " ++ selected ++ "\n        v : " ++ ty ++ " <- " ++ convert(kind, target, "get") ++ "(raw)\n        return Some{" ++ choice_con(choice, f) ++ "{v}}\n" ++ choice_reads(t, choice)

def choice_writes(ms: List<&2, M.Field>, +choice: String) -> String:
  match ms:
    case Nil{}: "\n"
    case Con{M.Field{f, number, kind, target, _, _, _, _}, t}:
      "        case " ++ choice_con(choice, f) ++ "{v}: [R.Field{" ++ U32.show(number) ++ ", " ++ convert(kind, target, "put") ++ "(v)}]\n" ++ choice_writes(t, choice)

def validate_member(kind: U32, number: U32, +target: String) -> String:
  match kind:
    case 9: "    case " ++ U32.show(number) ++ ": Maybe.is_some(&2, String, R.get_string(v))\n"
    case 11:
      +ty = M.name(target)
      "    case " ++ U32.show(number) ++ ": Maybe.is_some(&2, " ++ ty ++ ", " ++ ty ++ ".get(v))\n"
    case _: ""

def validate_cases(ms: List<&2, M.Field>) -> String:
  match ms:
    case Nil{}: ""
    case Con{M.Field{_, num, k, target, _, _, _, _}, t}: validate_member(k, num, target) ++ validate_cases(t)

def choice_validation(cases: String, +ty: String, +opt: String) -> String:
  match cases:
    case SNil{}:
      "def " ++ ty ++ ".validate(s: V.Choice) -> Maybe<&2, " ++ opt ++ ">:\n  V.Choice{n, fields, _} = s\n  " ++ ty ++ ".selected(n, fields)\n\n"
    case SCon{h, t}:
      valid = "def " ++ ty ++ ".valid(f: R.Field) -> Bool:\n  R.Field{n, v} = f\n  match n:\n" ++ SCon{h, t} ++ "    case _: True{}\n\n"
      compact = "def " ++ ty ++ ".validate(s: V.Choice) -> Maybe<&2, " ++ opt ++ ">:\n  V.Choice{n, fields, discarded} = s\n  do Maybe<&2, " ++ opt ++ ">:\n    ok : Unit <- V.checked(List.all(~&2, ~R.Field, ~" ++ ty ++ ".valid, discarded))\n    " ++ ty ++ ".selected(n, fields)\n\n"
      valid ++ compact

def oneof_code(ms: List<&2, M.Field>, +ty: String) -> String:
  match ms:
    case Nil{}: ""
    case Con{+h, +t}:
      +xs = {Con{h, t} : List<&2, M.Field>}
      +opt = "Maybe<&2, " ++ ty ++ ">"
      read = "def " ++ ty ++ ".selected(n: U32, fs: List<&2, R.Field>) -> Maybe<&2, " ++ opt ++ ">:\n  match n:\n" ++ choice_reads(xs, ty)
      validate = choice_validation(validate_cases(xs), ty, opt)
      pick = "def " ++ ty ++ ".read(fs: List<&2, R.Field>) -> Maybe<&2, " ++ opt ++ ">:\n  " ++ ty ++ ".validate(V.select_known(fs, V.Choice{0, Nil{}, Nil{}}))\n\n"
      write = "def " ++ ty ++ ".write(x: " ++ opt ++ ") -> List<&2, R.Field>:\n  match x:\n    case None{}: Nil{}\n    case Some{c}:\n      match c:\n" ++ choice_writes(xs, ty)
      read ++ validate ++ pick ++ write

def oneof_defs(gs: List<&2, String>, +n: String, +xs: List<&2, M.Field>, +i: U32) -> String:
  match gs:
    case Nil{}: ""
    case Con{_, t}: oneof_code(group_fields(xs, i), choice_type(n, i)) ++ oneof_defs(t, n, xs, U32.add(i, 1))

def unknown_slot(preserve: Bool) -> List<&2, Slot>:
  match preserve:
    case False{}: Nil{}
    case True{}: [Slot{"unknown_fields", "List<&2, R.Field>", "Nil{}", "Some{fs}", "unknown_fields", "0"}]

def message_slots(+fs: List<&2, M.Field>, gs: List<&2, String>, name: String, maps: Set(), entry: Bool, preserve: Bool) -> List<&2, Slot>:
  List.append(&2, Slot, fields(fs, maps, entry), List.append(&2, Slot, choices(gs, name, fs, 0), unknown_slot(preserve)))

def message_decl(m: M.Message, maps: Set(), preserve: Bool) -> String:
  M.Message{raw, +fs, +gs, entry} = m
  +n = M.name(raw)
  slots = message_slots(fs, gs, n, maps, entry, preserve)
  oneof_decls(gs, n, fs, 0) ++ "type " ++ n ++ " is Data:\n  " ++ n ++ "{" ++ join_slots(~slot_decl, slots) ++ "}\n\n"

def message_decls(msgs: List<&2, M.Message>, +maps: Set(), +preserve: Bool) -> List<(Unit -> String)>:
  match msgs:
    case Nil{}: Nil{}
    case Con{m, t}: Con{u => message_decl(m, maps, preserve), message_decls(t, maps, preserve)}

# Each enum is an open numeric type. Named constants and unknown numbers
# therefore take exactly the same round trip, including negative int32 values.
def constants(xs: List<&2, M.EnumValue>, +n: String) -> String:
  match xs:
    case Nil{}: ""
    case Con{M.EnumValue{name, v}, t}:
      "def " ++ n ++ ".value_" ++ M.ident(name) ++ "() -> " ++ n ++ ":\n  " ++ n ++ "{" ++ U32.show(v) ++ "}\n\n" ++ constants(t, n)

def enum_def(e: M.Enum) -> String:
  M.Enum{raw, vals} = e
  +n = M.name(raw)
  decl = "type " ++ n ++ " is Data:\n  " ++ n ++ "{number: U32}\n\n"
  get = "def " ++ n ++ ".get(v: R.Value) -> Maybe<&2, " ++ n ++ ">:\n  Maybe.map(&2, U32, " ++ n ++ ", x => " ++ n ++ "{x}, R.get_int32(v))\n\n"
  put = "def " ++ n ++ ".put(x: " ++ n ++ ") -> R.Value:\n  " ++ n ++ "{v} = x\n  R.put_int32(v)\n\n"
  decl ++ constants(vals, n) ++ get ++ put

def enum_defs(es: List<&2, M.Enum>) -> List<(Unit -> String)>:
  match es:
    case Nil{}: Nil{}
    case Con{e, t}: Con{u => enum_def(e), enum_defs(t)}

def key_code(k: U32, n: String) -> String:
  match k:
    case 3: "V.word_key(" ++ n ++ ")"
    case 4: "V.word_key(" ++ n ++ ")"
    case 6: "V.word_key(" ++ n ++ ")"
    case 8: "U32.show(Bool.to_u32(" ++ n ++ "))"
    case 9: n
    case 16: "V.word_key(" ++ n ++ ")"
    case 18: "V.word_key(" ++ n ++ ")"
    case _: "U32.show(" ++ n ++ ")"

def map_key(entry: Bool, +n: String, xs: List<&2, M.Field>, preserve: Bool) -> String:
  match entry xs:
    case True{} Con{M.Field{_, _, k, _, _, _, _, _}, _}:
      "def " ++ n ++ ".key(entry: " ++ n ++ ") -> String:\n  " ++ n ++ Bool.pick(String, preserve, "{key, _, _}", "{key, _}") ++ " = entry\n  " ++ key_code(k, "key") ++ "\n\n"
    case _ _: ""

def adapters(+n: String, +prefix: String) -> String:
  get = prefix ++ "def " ++ n ++ ".get(v: R.Value) -> Maybe<&2, " ++ n ++ ">:\n  do Maybe<&2, " ++ n ++ ">:\n    bytes : List<&2, U32> <- R.get_bytes(v)\n    " ++ n ++ ".decode(bytes)\n\n"
  put = prefix ++ "def " ++ n ++ ".put(x: " ++ n ++ ") -> R.Value:\n  V.blob(" ++ n ++ ".encode_checked(x))\n\n"
  get ++ put

def trailing_adapters(cyclic: Bool, n: String) -> String:
  match cyclic:
    case True{}: ""
    case False{}: adapters(n, "")

def init_message(m: M.Message, maps: Set(), +preserve: Bool) -> String:
  M.Message{raw, +fs, gs, +entry} = m
  +n = M.name(raw)
  slots = message_slots(fs, gs, n, maps, entry, preserve)
  "def " ++ n ++ ".default() -> " ++ n ++ ":\n  " ++ n ++ "{" ++ join_slots(~slot_zero, slots) ++ "}\n\n" ++ map_key(entry, n, fs, preserve)

def default_chunk(include: Bool, m: M.Message, maps: Set(), preserve: Bool, rest: List<(Unit -> String)>) -> List<(Unit -> String)>:
  match include:
    case False{}: rest
    case True{}: Con{u => init_message(m, maps, preserve), rest}

def defaults(xs: List<&2, M.Message>, +maps: Set(), +entries: Bool, +preserve: Bool) -> List<(Unit -> String)>:
  match xs:
    case Nil{}: Nil{}
    case Con{+m, t}:
      M.Message{_, _, _, entry} = m
      default_chunk(U32.is_eq(Bool.to_u32(entry), Bool.to_u32(entries)), m, maps, preserve, defaults(t, maps, entries, preserve))

def route_bucket(group: Maybe<&2, U32>, number: String) -> String:
  match group:
    case None{}: field_bucket(number)
    case Some{i}: oneof_bucket(i)

def wire_test(repeated: Bool, w: String) -> String:
  match repeated:
    case True{}: "V.repeated_wire(" ++ w ++ ", wire)"
    case False{}: "U32.is_eq(wire, " ++ w ++ ")"

def route_cases(fs: List<&2, M.Field>) -> String:
  match fs:
    case Nil{}: "    case _: 0\n\n"
    case Con{M.Field{_, num, k, _, rep, _, g, _}, t}:
      +number = U32.show(num)
      "    case " ++ number ++ ": Bool.pick(U32, " ++ wire_test(rep, wire(k)) ++ ", " ++ route_bucket(g, number) ++ ", 0)\n" ++ route_cases(t)

def in_oneof(f: M.Field) -> Bool:
  M.Field{_, _, _, _, _, _, group, _} = f
  Maybe.is_some(&2, U32, group)

# Small plain records decode faster with direct lookups. A shared index wins
# for wider records and also supplies oneof ordering and the unknown-field bag.
def need_index(slots: List<&2, Slot>, fields: List<&2, M.Field>, preserve: Bool) -> Bool:
  wide = Bool.not(List.is_empty(&2, Slot, List.drop(&2, Slot, slots, 4n)))
  preserve || wide || List.any(~&2, ~M.Field, ~in_oneof, fields)

def classifier(indexed: Bool, name: String, fs: List<&2, M.Field>) -> String:
  match indexed:
    case False{}: ""
    case True{}: "def " ++ name ++ ".bucket(number: U32, wire: U32) -> U32:\n  match number:\n" ++ route_cases(fs)

def build_index(indexed: Bool, name: String, preserve: Bool) -> String:
  match indexed:
    case False{}: ""
    case True{}: "    +index : V.FieldIndex = V.index(~" ++ name ++ ".bucket, " ++ Bool.pick(String, preserve, "True{}", "False{}") ++ ", fs)\n"

def message_defs(m: M.Message, maps: Set(), cyclic: Bool, +preserve: Bool) -> String:
  M.Message{raw, +fs, +gs, map_entry} = m
  +n = M.name(raw)
  +slots = message_slots(fs, gs, n, maps, map_entry, preserve)
  +indexed = need_index(slots, fs, preserve)
  +record = n ++ "{" ++ join_slots(~slot_name, slots) ++ "}"
  route = classifier(indexed, n, fs)
  read = "def " ++ n ++ ".decode(bytes: List<&2, U32>) -> Maybe<&2, " ++ n ++ ">:\n  do Maybe<&2, " ++ n ++ ">:\n    +fs : List<&2, R.Field> <- R.parse(bytes)\n" ++ build_index(indexed, n, preserve) ++ reads(slots, indexed) ++ "    return " ++ record ++ "\n\n"
  write = "def " ++ n ++ ".encode_checked(x: " ++ n ++ ") -> Maybe<&2, List<&2, U32>>:\n  " ++ record ++ " = x\n  out : List<&2, R.Field> = Nil{}\n" ++ writes(List.reverse(&2, Slot, slots)) ++ "  R.render_checked(out)\n\n"
  encode = "def " ++ n ++ ".encode(x: " ++ n ++ ") -> Maybe<&2, List<&2, U32>>:\n  " ++ n ++ ".encode_checked(x)\n\n"
  route ++ oneof_defs(gs, n, fs, 0) ++ read ++ write ++ encode ++ trailing_adapters(cyclic, n)

# Visit child types before emitting the codec that calls them. A reference to
# an active ancestor needs a forward adapter. All other adapters can follow
# their codec definitions, including users of a recursive type.
type Visit is Data:
  EnterType{name: String}
  FinishType{message: M.Message}

type Walk is Data:
  Walk{todo: List<&2, Visit>, unvisited: Map<&2, M.Message>, active: Set(), forward: Set(), finished: List<&2, M.Message>}

def visit_fields(xs: List<&2, M.Field>, rest: List<&2, Visit>) -> List<&2, Visit>:
  match xs:
    case Nil{}: rest
    case Con{M.Field{_, _, 11, name, _, _, _, _}, t}: Con{EnterType{name}, visit_fields(t, rest)}
    case Con{_, t}: visit_fields(t, rest)

def forward_if(active: Bool, names: Set(), target: String) -> Set():
  match active:
    case True{}: Set.add(names, target)
    case False{}: names

def enter(popped: Map<&2, M.Message> & Maybe<&2, M.Message>, +name: String, todo: List<&2, Visit>, +active: Set(), forward: Set(), finished: List<&2, M.Message>) -> Walk:
  match popped:
    case (remaining, Some{+m}):
      M.Message{_, fields, _, _} = m
      Walk{visit_fields(fields, Con{FinishType{m}, todo}), remaining, Set.add(active, name), forward, finished}
    case (remaining, None{}):
      back_edge = set_hit(Set.has(active, name))
      Walk{todo, remaining, active, forward_if(back_edge, forward, name), finished}

def walk_step(state: Walk) -> Walk:
  match state:
    case Walk{Con{EnterType{+name}, rest}, remaining, active, forward, finished}:
      enter(Map.pop(&2, M.Message, remaining, name), name, rest, active, forward, finished)
    case Walk{Con{FinishType{+m}, rest}, remaining, active, forward, finished}:
      M.Message{name, _, _, _} = m
      Walk{rest, remaining, Set.del(active, name), forward, Con{m, finished}}
    case done: done

def walk(fuel: Nat, state: Walk) -> Set() & List<&2, M.Message>:
  match fuel state:
    case 0n Walk{_, _, _, forward, finished}: (forward, List.reverse(&2, M.Message, finished))
    case 1n+p Walk{Nil{}, _, _, forward, finished}: (forward, List.reverse(&2, M.Message, finished))
    case 1n+p state: walk(p, walk_step(state))

# Every root is entered once and every visited message adds one leave event
# and at most one enter per field. This bounds the work even for mutual cycles.
def order(xs: List<&2, M.Message>, remaining: Map<&2, M.Message>, roots: List<&2, Visit>, fuel: Nat) -> Set() & List<&2, M.Message>:
  match xs:
    case Nil{}: walk(fuel, Walk{List.reverse(&2, Visit, roots), remaining, Set.new(), Set.new(), Nil{}})
    case Con{+m, t}:
      M.Message{+name, fields, _, _} = m
      budget = Nat.add(2n, List.length(&2, M.Field, fields))
      order(t, Map.set(&2, M.Message, remaining, name, m), Con{EnterType{name}, roots}, Nat.add(budget, fuel))

def append_chunks(a: List<(Unit -> String)>, b: List<(Unit -> String)>) -> List<(Unit -> String)>:
  List.append(&1, Unit -> String, a, b)

def definitions(xs: List<&2, M.Message>, +forward: Set(), +maps: Set(), +preserve: Bool) -> List<(Unit -> String)>:
  match xs:
    case Nil{}: Nil{}
    case Con{+m, t}:
      M.Message{name, _, _, _} = m
      declared = set_hit(Set.has(forward, name))
      Con{u => message_defs(m, maps, declared, preserve), definitions(t, forward, maps, preserve)}

def forward_adapters(names: List<&2, String>) -> List<(Unit -> String)>:
  match names:
    case Nil{}: Nil{}
    case Con{n, t}: Con{u => adapters(M.name(n), "@unsafe "), forward_adapters(t)}

def ordered_definitions(result: Set() & List<&2, M.Message>, maps: Set(), preserve: Bool) -> List<(Unit -> String)>:
  (+forward, xs) = result
  append_chunks(forward_adapters(Set.to_list(forward)), definitions(xs, forward, maps, preserve))

# Keep each emission lazy. The plugin writes and releases each source fragment
# as it goes, including when a request contains thousands of message types.
def emit_chunks(+msgs: List<&2, M.Message>, enums: List<&2, M.Enum>, +preserve_unknown: Bool) -> List<(Unit -> String)>:
  +maps = map_set(msgs, Set.new())
  decls = message_decls(msgs, maps, preserve_unknown)
  ordinary = defaults(msgs, maps, False{}, preserve_unknown)
  entries = defaults(msgs, maps, True{}, preserve_unknown)
  impls = ordered_definitions(order(msgs, MTip{}, Nil{}, 0n), maps, preserve_unknown)
  append_chunks(enum_defs(enums), append_chunks(decls, append_chunks(ordinary, append_chunks(entries, impls))))
