import Base

# Descriptor names use protoc's absolute form, e.g. ".acme.v1.Echo.Request".
type Field is Data:
  Field{name: String, number: U32, kind: U32, target: String, repeated: Bool, optional: Bool, oneof: Maybe<&2, U32>, packed: Bool}

type Message is Data:
  Message{name: String, fields: List<&2, Field>, oneofs: List<&2, String>, map_entry: Bool}

type EnumValue is Data:
  EnumValue{name: String, number: U32}

type Enum is Data:
  Enum{name: String, values: List<&2, EnumValue>}

type Method is Data:
  Method{name: String, input: String, output: String, client_stream: Bool, server_stream: Bool}

type Service is Data:
  Service{name: String, methods: List<&2, Method>}

def ident_char(code: U32, tail: String) -> String:
  match code:
    case 95: "_0" ++ tail
    case 46: "_" ++ tail
    case n: SCon{Chr{n}, tail}

def ident(s: String) -> String:
  match s:
    case SNil{}: ""
    case SCon{c, t}: ident_char(Char.to_u32(c), ident(t))

def name(absolute: String) -> String:
  "PB_" ++ ident(String.drop(absolute, 1n))
