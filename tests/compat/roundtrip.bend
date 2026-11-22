import Base
import ./archive.bend as Tree
import ./catalog.bend as Items

# Both invocations share support files, but keep distinct schema modules.
# The child carries a future varint. Its parent carries an obsolete group,
# an unknown fixed32 field, and the known label number with another wire type.
def edit(node: Maybe<&2, Tree.PB_tree_Node>) -> Maybe<&2, List<&2, U32>>:
  match node:
    case Some{Tree.PB_tree_Node{"", kids, link, extras}}:
      Tree.PB_tree_Node.encode(Tree.PB_tree_Node{"X", kids, link, extras})
    case _: None{}

def checked(bytes: Maybe<&2, List<&2, U32>>, item: Maybe<&2, List<&2, U32>>) -> Bool:
  match bytes item:
    case Some{[10, 1, 88, 18, 3, 72, 150, 1, 83, 88, 7, 84, 101, 1, 2, 3, 4, 8, 9]} Some{[50, 7, 10, 1, 75, 16, 1, 24, 42]}: True{}
    case _ _: False{}

def map_entry() -> Maybe<&2, List<&2, U32>>:
  do Maybe<&2, List<&2, U32>>:
    value : Items.PB_sample_Item <- Items.PB_sample_Item.decode([50, 7, 10, 1, 75, 16, 1, 24, 42])
    Items.PB_sample_Item.encode(value)

def finish(ok: Bool) -> IO(Unit):
  match ok:
    case True{}: IO.pure(Unit, Unit{})
    case False{}: IO.die(Unit, 1, "Lost unknown fields while editing a generated message")

def main() -> IO(Unit):
  bytes : List<&2, U32> = [18, 3, 72, 150, 1, 83, 88, 7, 84, 101, 1, 2, 3, 4, 8, 9]
  finish(checked(edit(Tree.PB_tree_Node.decode(bytes)), map_entry()))
