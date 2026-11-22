# Schema and text-format inputs consumed by protoc during the integration tests.
import Base
import ../tools/host.bend as Host

def common() -> String:
  String.join([
    "syntax = \"proto3\";",
    "package sample.types;",
    "",
    "message Label { string text = 1; }",
    "enum State { UNKNOWN = 0; ENABLED = 1; NEGATIVE = -1; }"
  ], "\n") ++ "\n"

def item_schema() -> String:
  String.join([
    "syntax = \"proto3\";",
    "package sample;",
    "import \"common.proto\";",
    "",
    "message Item {",
    "  message Metadata { fixed32 checksum = 1; }",
    "  optional uint32 count = 1;",
    "  repeated sint32 deltas = 2;",
    "  sample.types.Label label = 3;",
    "  bytes payload = 4;",
    "  sample.types.State state = 5;",
    "  map<string, uint64> totals = 6;",
    "  Metadata meta = 7;",
    "  repeated fixed64 ids = 8 [packed = false];",
    "  oneof detail { string note = 9; bool enabled = 10; }",
    "}"
  ], "\n") ++ "\n"

def echo() -> String:
  String.join([
    "syntax = \"proto3\";",
    "package demo;",
    "",
    "message Value {",
    "  uint32 value = 1;",
    "}",
    "",
    "service Echo {",
    "  rpc Say(Value) returns (Value);",
    "  rpc List(Value) returns (stream Value);",
    "}"
  ], "\n") ++ "\n"

def tree() -> String:
  String.join([
    "syntax = \"proto3\";",
    "package tree;",
    "",
    "message Node {",
    "  string label = 1;",
    "  repeated Node children = 2;",
    "  oneof link {",
    "    Node peer = 3;",
    "    uint32 id = 4;",
    "  }",
    "}"
  ], "\n") ++ "\n"

def upload() -> String:
  String.join([
    "syntax = \"proto3\";",
    "message Chunk {}",
    "service Upload { rpc Put(stream Chunk) returns (Chunk); }"
  ], "\n") ++ "\n"

def legacy() -> String:
  String.join([
    "syntax = \"proto2\";",
    "message Old { required bool value = 1; }"
  ], "\n") ++ "\n"

def item_with_count(count: U32) -> String:
  String.join([
    "count: " ++ U32.show(count),
    "deltas: -1",
    "deltas: 300",
    "label { text: \"café\" }",
    "payload: \"\\000\\377x\"",
    "state: NEGATIVE",
    "totals { key: \"total\" value: 18446744073709551615 }",
    "meta { checksum: 4294967295 }",
    "ids: 9223372036854775808",
    "enabled: false"
  ], "\n") ++ "\n"

def item_text() -> String:
  item_with_count(0)

def save(path: String, contents: String) -> IO(Unit):
  do IO<Unit>:
    file : File <- IO.try(File, File.open(path, "x"))
    result : File & Result<&1, &1, U32 & String, Unit> <- File.write(file, contents)
    Host.finish_write(result)

def write(+dir: String) -> IO(Unit):
  do IO<Unit>:
    save(dir ++ "/common.proto", common())
    save(dir ++ "/fixture.proto", item_schema())
    save(dir ++ "/echo.proto", echo())
    save(dir ++ "/tree.proto", tree())
    save(dir ++ "/upload.proto", upload())
    save(dir ++ "/old.proto", legacy())
    save(dir ++ "/item.textproto", item_text())

def run(args: List<String>) -> IO(Unit):
  match args:
    case [_, dir]: write(dir)
    case _: IO.die(Unit, 1, "usage: bend tests/fixtures.bend <empty directory>")

def main() -> IO(Unit):
  IO.bind(List<String>, Unit, IO.args(), run)
