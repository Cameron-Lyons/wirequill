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
  Slot{label: String, ty: String, zero: String, read: String, write: String}

def singular_slot(optional: Bool, +n: String, +ty: String, +num: String, get: String, put: String, lookup: String, +d: String) -> Slot:
  match optional:
    case True{}:
      Slot{n, "Maybe<&2, " ++ ty ++ ">", "None{}", "V.optional(~" ++ ty ++ ", ~" ++ get ++ ", " ++ lookup ++ ")", "V.emit_optional(~" ++ ty ++ ", ~" ++ put ++ ", " ++ num ++ ", " ++ n ++ ")"}
    case False{}:
      Slot{n, ty, d, "V.scalar(~" ++ ty ++ ", ~" ++ get ++ ", " ++ lookup ++ ", " ++ d ++ ")", "V.emit_scalar(" ++ num ++ ", " ++ put ++ "(" ++ n ++ "))"}

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
      Slot{n, "Map<&2, " ++ ty ++ ">", "MTip{}", read, write}
    case False{}:
      +ty = bare(kind, target)
      +w = wire(kind)
      read = "V.many(~" ++ ty ++ ", ~" ++ convert(kind, target, "get") ++ ", " ++ num ++ ", " ++ w ++ ", fs)"
      write = many_write(packed, ty, convert(kind, target, "put"), num, w, n)
      Slot{n, "List<&2, " ++ ty ++ ">", "Nil{}", read, write}

def field_slot(repeated: Bool, is_map: Bool, +n: String, +num: String, +kind: U32, +target: String, optional: Bool, packed: Bool) -> Slot:
  match repeated kind:
    case True{} _: repeated_slot(is_map, n, num, kind, target, packed)
    case False{} 11:
      +ty = M.name(target)
      read = "V.optional(~" ++ ty ++ ", ~" ++ ty ++ ".get, R.child(" ++ num ++ ", fs))"
      write = "V.emit_optional(~" ++ ty ++ ", ~" ++ ty ++ ".put, " ++ num ++ ", " ++ n ++ ")"
      Slot{n, "Maybe<&2, " ++ ty ++ ">", "None{}", read, write}
    case False{} k: scalar_slot(n, num, k, target, optional)

def slot_decl(s: Slot) -> String:
  Slot{n, t, _, _, _} = s
  n ++ ": " ++ t

def slot_name(s: Slot) -> String:
  Slot{n, _, _, _, _} = s
  n

def slot_zero(s: Slot) -> String:
  Slot{_, _, z, _, _} = s
  z

def join_slots(~show: Slot -> String, xs: List<&2, Slot>) -> String:
  match xs:
    case Nil{}: ""
    case Con{h, Nil{}}: show(h)
    case Con{h, Con{hh, tt}}: show(h) ++ ", " ++ join_slots(~show, Con{hh, tt})

def reads(xs: List<&2, Slot>) -> String:
  match xs:
    case Nil{}: ""
    case Con{Slot{n, t, _, read, _}, rest}: "    " ++ n ++ " : " ++ t ++ " <- " ++ read ++ "\n" ++ reads(rest)

def writes(reversed: List<&2, Slot>) -> String:
  match reversed:
    case Nil{}: ""
    case Con{Slot{_, _, _, _, write}, rest}:
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
      Slot{name, ty, ty ++ ".default()", read, "[R.Field{2, " ++ ty ++ ".put(" ++ name ++ ")}]"}
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

def choice_slot(members: List<&2, M.Field>, +n: String, +name: String, i: U32, rest: List<&2, Slot>) -> List<&2, Slot>:
  match members:
    case Nil{}: rest
    case Con{_, _}:
      +ty = choice_type(n, i)
      +label = "o_" ++ M.ident(name)
      Con{Slot{label, "Maybe<&2, " ++ ty ++ ">", "None{}", ty ++ ".read(fs)", ty ++ ".write(" ++ label ++ ")"}, rest}

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

def members(ms: List<&2, M.Field>) -> String:
  match ms:
    case Nil{}: "Nil{}"
    case Con{M.Field{_, number, kind, _, _, _, _, _}, t}:
      "Con{V.Member{" ++ U32.show(number) ++ ", " ++ wire(kind) ++ "}, " ++ members(t) ++ "}"

def validate_member(kind: U32, +number: U32, +target: String) -> String:
  match kind:
    case 9:
      "    unused_" ++ U32.show(number) ++ " : List<&2, String> <- V.many(~String, ~R.get_string, " ++ U32.show(number) ++ ", 2, discarded)\n"
    case 11:
      +ty = M.name(target)
      "    unused_" ++ U32.show(number) ++ " : List<&2, " ++ ty ++ "> <- V.many(~" ++ ty ++ ", ~" ++ ty ++ ".get, " ++ U32.show(number) ++ ", 2, discarded)\n"
    case _: ""

def validate_discarded(ms: List<&2, M.Field>) -> String:
  match ms:
    case Nil{}: ""
    case Con{M.Field{_, num, k, target, _, _, _, _}, t}: validate_member(k, num, target) ++ validate_discarded(t)

def oneof_code(ms: List<&2, M.Field>, +ty: String) -> String:
  match ms:
    case Nil{}: ""
    case Con{+h, +t}:
      +xs = {Con{h, t} : List<&2, M.Field>}
      +opt = "Maybe<&2, " ++ ty ++ ">"
      read = "def " ++ ty ++ ".selected(n: U32, fs: List<&2, R.Field>) -> Maybe<&2, " ++ opt ++ ">:\n  match n:\n" ++ choice_reads(xs, ty)
      validate = "def " ++ ty ++ ".validate(s: V.Choice) -> Maybe<&2, " ++ opt ++ ">:\n  V.Choice{number, rest, +discarded} = s\n  do Maybe<&2, " ++ opt ++ ">:\n" ++ validate_discarded(xs) ++ "    " ++ ty ++ ".selected(number, rest)\n\n"
      pick = "def " ++ ty ++ ".read(fs: List<&2, R.Field>) -> Maybe<&2, " ++ opt ++ ">:\n  " ++ ty ++ ".validate(V.select(fs, " ++ members(xs) ++ ", V.Choice{0, Nil{}, Nil{}}))\n\n"
      write = "def " ++ ty ++ ".write(x: " ++ opt ++ ") -> List<&2, R.Field>:\n  match x:\n    case None{}: Nil{}\n    case Some{c}:\n      match c:\n" ++ choice_writes(xs, ty)
      read ++ validate ++ pick ++ write

def oneof_defs(gs: List<&2, String>, +n: String, +xs: List<&2, M.Field>, +i: U32) -> String:
  match gs:
    case Nil{}: ""
    case Con{_, t}: oneof_code(group_fields(xs, i), choice_type(n, i)) ++ oneof_defs(t, n, xs, U32.add(i, 1))

def message_decls(msgs: List<&2, M.Message>, +maps: Set()) -> String:
  match msgs:
    case Nil{}: ""
    case Con{M.Message{raw, +fs, +gs, map_entry}, t}:
      +n = M.name(raw)
      slots = List.append(&2, Slot, fields(fs, maps, map_entry), choices(gs, n, fs, 0))
      oneof_decls(gs, n, fs, 0) ++ "type " ++ n ++ " is Data:\n  " ++ n ++ "{" ++ join_slots(~slot_decl, slots) ++ "}\n\n" ++ message_decls(t, maps)

# Each enum is an open numeric type. Named constants and unknown numbers
# therefore take exactly the same round trip, including negative int32 values.
def constants(xs: List<&2, M.EnumValue>, +n: String) -> String:
  match xs:
    case Nil{}: ""
    case Con{M.EnumValue{name, v}, t}:
      "def " ++ n ++ ".value_" ++ M.ident(name) ++ "() -> " ++ n ++ ":\n  " ++ n ++ "{" ++ U32.show(v) ++ "}\n\n" ++ constants(t, n)

def enum_defs(es: List<&2, M.Enum>) -> String:
  match es:
    case Nil{}: ""
    case Con{M.Enum{raw, vals}, t}:
      +n = M.name(raw)
      decl = "type " ++ n ++ " is Data:\n  " ++ n ++ "{number: U32}\n\n"
      get = "def " ++ n ++ ".get(v: R.Value) -> Maybe<&2, " ++ n ++ ">:\n  Maybe.map(&2, U32, " ++ n ++ ", x => " ++ n ++ "{x}, R.get_int32(v))\n\n"
      put = "def " ++ n ++ ".put(x: " ++ n ++ ") -> R.Value:\n  " ++ n ++ "{v} = x\n  R.put_int32(v)\n\n"
      decl ++ constants(vals, n) ++ get ++ put ++ enum_defs(t)

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

def map_key(entry: Bool, +n: String, xs: List<&2, M.Field>) -> String:
  match entry xs:
    case True{} Con{M.Field{_, _, k, _, _, _, _, _}, _}:
      "def " ++ n ++ ".key(entry: " ++ n ++ ") -> String:\n  " ++ n ++ "{key, _} = entry\n  " ++ key_code(k, "key") ++ "\n\n"
    case _ _: ""

def adapters(+n: String, +prefix: String) -> String:
  get = prefix ++ "def " ++ n ++ ".get(v: R.Value) -> Maybe<&2, " ++ n ++ ">:\n  do Maybe<&2, " ++ n ++ ">:\n    bytes : List<&2, U32> <- R.get_bytes(v)\n    " ++ n ++ ".decode(bytes)\n\n"
  put = prefix ++ "def " ++ n ++ ".put(x: " ++ n ++ ") -> R.Value:\n  V.blob(" ++ n ++ ".encode_checked(x))\n\n"
  get ++ put

def trailing_adapters(cyclic: Bool, n: String) -> String:
  match cyclic:
    case True{}: ""
    case False{}: adapters(n, "")

def init_message(include: Bool, +m: M.Message, maps: Set()) -> String:
  match include:
    case False{}: ""
    case True{}:
      M.Message{raw, +fs, +gs, +entry} = m
      +n = M.name(raw)
      slots = List.append(&2, Slot, fields(fs, maps, entry), choices(gs, n, fs, 0))
      "def " ++ n ++ ".default() -> " ++ n ++ ":\n  " ++ n ++ "{" ++ join_slots(~slot_zero, slots) ++ "}\n\n" ++ map_key(entry, n, fs)

def defaults(xs: List<&2, M.Message>, +maps: Set(), +entries: Bool) -> String:
  match xs:
    case Nil{}: ""
    case Con{+m, t}:
      M.Message{_, _, _, entry} = m
      init_message(U32.is_eq(Bool.to_u32(entry), Bool.to_u32(entries)), m, maps) ++ defaults(t, maps, entries)

def message_defs(m: M.Message, maps: Set(), +cyclic: Bool) -> String:
  M.Message{raw, +fs, +gs, +map_entry} = m
  +n = M.name(raw)
  +slots = List.append(&2, Slot, fields(fs, maps, map_entry), choices(gs, n, fs, 0))
  +record = n ++ "{" ++ join_slots(~slot_name, slots) ++ "}"
  read = "def " ++ n ++ ".decode(bytes: List<&2, U32>) -> Maybe<&2, " ++ n ++ ">:\n  do Maybe<&2, " ++ n ++ ">:\n    +fs : List<&2, R.Field> <- R.parse(bytes)\n" ++ reads(slots) ++ "    return " ++ record ++ "\n\n"
  write = "def " ++ n ++ ".encode_checked(x: " ++ n ++ ") -> Maybe<&2, List<&2, U32>>:\n  " ++ record ++ " = x\n  out : List<&2, R.Field> = Nil{}\n" ++ writes(List.reverse(&2, Slot, slots)) ++ "  R.render_checked(out)\n\n"
  encode = "def " ++ n ++ ".encode(x: " ++ n ++ ") -> Maybe<&2, List<&2, U32>>:\n  " ++ n ++ ".encode_checked(x)\n\n"
  oneof_defs(gs, n, fs, 0) ++ read ++ write ++ encode ++ trailing_adapters(cyclic, n)

# Bend checks definitions in declaration order. Emit dependencies first.
def ready(fs: List<&2, M.Field>, +done: Set()) -> Bool:
  match fs:
    case Nil{}: True{}
    case Con{M.Field{_, _, 11, target, _, _, _, _}, t}:
      set_hit(Set.has(done, target)) && ready(t, done)
    case Con{_, t}: ready(t, done)

type Ordered is Data:
  Ordered{ready: List<&2, M.Message>, pending: List<&2, M.Message>, seen: Set()}

def msg_name(m: M.Message) -> String:
  M.Message{name, _, _, _} = m
  name

def schedule(hit: Bool, +m: M.Message, xs: Ordered) -> Ordered:
  match hit xs:
    case True{} Ordered{yes, no, seen}:
      Ordered{Con{m, yes}, no, Set.add(seen, msg_name(m))}
    case False{} Ordered{yes, no, seen}: Ordered{yes, Con{m, no}, seen}

def partition(xs: List<&2, M.Message>, +seen: Set()) -> Ordered:
  match xs:
    case Nil{}: Ordered{Nil{}, Nil{}, seen}
    case Con{+m, t}:
      M.Message{_, fs, _, _} = m
      schedule(ready(fs, seen), m, partition(t, seen))

def definitions(xs: List<&2, M.Message>, +maps: Set(), +cyclic: Bool) -> String:
  match xs:
    case Nil{}: ""
    case Con{m, t}: message_defs(m, maps, cyclic) ++ definitions(t, maps, cyclic)

def cycle_adapters(xs: List<&2, M.Message>) -> String:
  match xs:
    case Nil{}: ""
    case Con{M.Message{n, _, _, _}, t}: adapters(M.name(n), "@unsafe ") ++ cycle_adapters(t)

def sorted_step(o: Ordered, +maps: Set(), next: List<&2, M.Message> -> Set() -> String) -> String:
  match o:
    case Ordered{Nil{}, +pending, _}: cycle_adapters(pending) ++ definitions(pending, maps, True{})
    case Ordered{Con{h, t}, pending, seen}: definitions(Con{h, t}, maps, False{}) ++ next(pending, seen)

def sorted(fuel: Nat, xs: List<&2, M.Message>, seen: Set(), +maps: Set()) -> String:
  match fuel:
    case 0n: ""
    case 1n+p: sorted_step(partition(xs, seen), maps, rest => done => sorted(p, rest, done, maps))

def emit(+msgs: List<&2, M.Message>, enums: List<&2, M.Enum>) -> String:
  +maps = map_set(msgs, Set.new())
  enum_defs(enums) ++ message_decls(msgs, maps) ++ defaults(msgs, maps, False{}) ++ defaults(msgs, maps, True{}) ++ sorted(Succ{List.length(&2, M.Message, msgs)}, msgs, Set.new(), maps)
