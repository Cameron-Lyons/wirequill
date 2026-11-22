# Bake the portable support modules into the executable, so protoc can invoke
# the installed plugin from any directory. Run from the project root at build time.
import Base

import ./host.bend as Host

def literal_lines(xs: List<&2, String>) -> String:
  match xs:
    case Nil{}: ""
    case Con{x, Nil{}}: "    " ++ String.quote(x)
    case Con{x, rest}: "    " ++ String.quote(x) ++ ",\n" ++ literal_lines(rest)

def module(name: String) -> IO(String):
  do IO<String>:
    +id : String = name
    src : String <- Host.read_text(id ++ ".bend")
    return "def " ++ id ++ "() -> String:\n  String.join([\n" ++ literal_lines(String.lines(src)) ++ "\n  ], \"\\n\")\n\n"

def source() -> IO(String):
  do IO<String>:
    r : String <- module("runtime")
    m : String <- module("message_values")
    g : String <- module("grpc_runtime")
    return "import Base\n\n" ++ r ++ m ++ g
