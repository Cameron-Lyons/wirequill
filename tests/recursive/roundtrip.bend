import Base
import ./schema.bend as S

def good(result: Maybe<&2, List<&2, U32>>) -> Bool:
  match result:
    case Some{[18, 3, 10, 1, 88, 26, 2, 32, 7]}: True{}
    case _: False{}

def is_peer(ref: Maybe<&2, S.Oneof_0_PB_tree_Node>) -> Bool:
  match ref:
    case Some{S.Choice_0_PB_tree_Node_peer{S.PB_tree_Node{"", Nil{}, Some{S.Choice_0_PB_tree_Node_id{7}}}}}: True{}
    case _: False{}

def expected(node: S.PB_tree_Node) -> Bool:
  match node:
    case S.PB_tree_Node{"", [S.PB_tree_Node{"X", Nil{}, None{}}], ref}: is_peer(ref)
    case _: False{}

def roundtrip(result: Maybe<&2, S.PB_tree_Node>) -> Bool:
  match result:
    case Some{+tree}: expected(tree) && good(S.PB_tree_Node.encode(tree))
    case None{}: False{}

def finish(ok: Bool) -> IO(Unit):
  match ok:
    case True{}: IO.pure(Unit, Unit{})
    case False{}: IO.die(Unit, 1, "recursive message or oneof handling failed")

def mutual(result: Maybe<&2, S.PB_tree_Envelope>) -> Bool:
  match result:
    case Some{S.PB_tree_Envelope{Some{S.PB_tree_Left{Some{S.PB_tree_Right{Some{S.PB_tree_Left{None{}}}}}}}}}: True{}
    case _: False{}

def main() -> IO(Unit):
  # The first peer is cleared by the id and must not merge into the later peer.
  wire : List<&2, U32> = [18, 3, 10, 1, 88, 26, 3, 10, 1, 89, 32, 9, 26, 2, 32, 7]
  corrupt : List<&2, U32> = [26, 3, 10, 1, 255, 32, 9]
  do IO<Unit>:
    finish(roundtrip(S.PB_tree_Node.decode(wire)) && Maybe.is_none(&2, S.PB_tree_Node, S.PB_tree_Node.decode(corrupt)))
    finish(mutual(S.PB_tree_Envelope.decode([10, 4, 10, 2, 10, 0])))
