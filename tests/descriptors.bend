import Base
import ../descriptors.bend as D
import ../descriptor_wire.bend as W
import ../model.bend as M
import ../runtime.bend as R

def text_field(tag: U32, s: String) -> R.Field:
  R.Field{tag, R.put_string(s)}

def number_field(tag: U32, n: U32) -> R.Field:
  R.Field{tag, R.Var{0, n}}

def object_field(tag: U32, fields: W.Doc) -> R.Field:
  R.Field{tag, R.Blob{Maybe.default(&2, List<&2, U32>, R.render_checked(fields), Nil{})}}

def request(fields: W.Doc) -> W.Checked(D.Schema):
  legacy = object_field(15, [text_field(1, "legacy.proto"), text_field(2, "old"), object_field(4, [text_field(1, "Legacy")])])
  # As in an ordinary custom-options import, the proto2 file has no syntax
  # tag and is included in proto_file even though it isn't a generated root.
  file = object_field(15, text_field(1, "api.proto") <> text_field(3, "legacy.proto") <> text_field(12, "proto3") <> fields)
  D.request([text_field(1, "api.proto"), legacy, file])

def grouped(real: U32) -> W.Checked(D.Schema):
  selected = object_field(2, [text_field(1, "selected"), number_field(3, 1), number_field(5, 8), number_field(9, real)])
  count = object_field(2, [text_field(1, "count"), number_field(3, 2), number_field(5, 13), number_field(9, 1), number_field(17, 1)])
  choice = object_field(8, [text_field(1, "choice")])
  synthetic = object_field(8, [text_field(1, "_count")])
  # Singular package fields follow the ordinary last-occurrence rule.
  request([text_field(2, "earlier"), text_field(2, "api.types"), object_field(4, [text_field(1, "Item"), selected, count, choice, synthetic])])

def kept_groups(r: W.Checked(D.Schema)) -> Bool:
  match r:
    case Done{D.Schema{[M.Message{name, [M.Field{first, 1, 8, _, _, False{}, Some{0}, _}, M.Field{second, 2, 13, _, _, True{}, None{}, _}], [group], False{}}], Nil{}, Nil{}}}:
      String.eq(name, ".api.types.Item") && String.eq(first, "selected") && String.eq(second, "count") && String.eq(group, "choice")
    case _: False{}

def unsupported_type() -> W.Checked(D.Schema):
  f = object_field(2, [text_field(1, "child"), number_field(3, 1), number_field(5, 11), text_field(6, ".old.Legacy")])
  request([object_field(4, [text_field(1, "Item"), f])])

def scalar(name: String, n: U32) -> R.Field:
  object_field(2, [text_field(1, name), number_field(3, n), number_field(5, 13)])

def duplicates(second: R.Field) -> W.Checked(D.Schema):
  request([object_field(4, [text_field(1, "Item"), scalar("a", 1), second])])

def duplicate_symbol() -> W.Checked(D.Schema):
  # Messages and enums share a protobuf namespace and a generated type prefix.
  value = object_field(2, [text_field(1, "UNKNOWN"), number_field(2, 0)])
  request([object_field(4, [text_field(1, "Item")]), object_field(5, [text_field(1, "Item"), value])])

def merging_options() -> W.Checked(U32):
  first = object_field(8, [number_field(2, 1)])
  second = object_field(8, [number_field(2, 0)])
  do W.Checked<U32>:
    doc : W.Doc <- W.sub([first, second], 8)
    W.number(doc, 2, 1)

def failed(r: W.Checked(D.Schema), message: String) -> Bool:
  match r:
    case Fail{diagnostic}: String.contains(diagnostic, message)
    case Done{_}: False{}

def merged(r: W.Checked(U32)) -> Bool:
  match r:
    case Done{0}: True{}
    case _: False{}

def check(ok: Bool, msg: String) -> IO(Unit):
  match ok:
    case True{}: IO.pure(Unit, Unit{})
    case False{}: IO.die(Unit, 1, msg)

def main() -> IO(Unit):
  do IO<Unit>:
    check(kept_groups(grouped(0)), "Custom-option imports, package overrides, or synthetic oneofs decoded incorrectly")
    check(failed(grouped(2), "Invalid oneof membership"), "Accepted a field referencing a missing oneof")
    check(failed(unsupported_type(), ".Item.child: .old.Legacy"), "Accepted a missing message type")
    check(failed(request([text_field(2, "a..b")]), "Invalid protobuf package"), "Accepted an invalid package identifier")
    check(failed(duplicates(scalar("a", 2)), "Duplicate field name: .Item.a"), "Accepted duplicate record labels")
    check(failed(duplicates(scalar("b", 1)), "Duplicate field number 1 in .Item"), "Accepted colliding wire tags")
    check(failed(duplicate_symbol(), "Duplicate protobuf declaration: .Item"), "Accepted colliding generated type names")
    check(merged(merging_options()), "Repeated descriptor options failed to merge")
