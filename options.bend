import Base
import ./descriptor_wire.bend as W

type Options is Data:
  Options{module_name: String, preserve_unknown: Bool}

type Settings is Data:
  Settings{module_name: Maybe<&2, String>, preserve_unknown: Bool}

def module_name(+s: String) -> W.Checked(String):
  +lower = String.to_lower(s)
  reserved = String.eq(lower, "runtime") || String.eq(lower, "message_values") || String.eq(lower, "grpc_runtime")
  do W.Checked<String>:
    valid : Unit <- W.require(W.is_id(s), "module must be a single identifier")
    free : Unit <- W.require(Bool.not(reserved), "module conflicts with a generated support file: " ++ s)
    return s

def setting(preserve: Bool, is_module: Bool, +arg: String, state: Settings) -> W.Checked(Settings):
  match preserve is_module state:
    case True{} _ Settings{name, False{}}: Done{Settings{name, True{}}}
    case True{} _ Settings{_, True{}}: Fail{"Duplicate generator parameter: preserve_unknown"}
    case _ True{} Settings{None{}, keep}:
      do W.Checked<Settings>:
        n : String <- module_name(String.drop(arg, 7n))
        return Settings{Some{n}, keep}
    case _ True{} Settings{Some{_}, _}: Fail{"Duplicate generator parameter: module"}
    case _ _ _: Fail{"Unknown generator parameter: " ++ arg}

def options(xs: List<&2, String>, state: Settings) -> W.Checked(Options):
  match xs:
    case Nil{}:
      Settings{name, keep} = state
      Done{Options{Maybe.default(&2, String, name, "schema"), keep}}
    case Con{+arg, rest}:
      do W.Checked<Options>:
        next : Settings <- setting(String.eq(arg, "preserve_unknown"), String.starts_with(arg, "module="), arg, state)
        options(rest, next)

def parse(s: String) -> W.Checked(Options):
  match s:
    case "": Done{Options{"schema", False{}}}
    case text: options(String.split(text, ','), Settings{None{}, False{}})
