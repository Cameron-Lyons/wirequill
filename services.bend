import Base
import ./model.bend as M

def imports(services: List<&2, M.Service>) -> String:
  match services:
    case Nil{}: ""
    case Con{_, _}:
      +hub = {"import 0xc8d18670ba37041507e7f53cc7972ec6/src/" : String}
      "import ./grpc_runtime.bend as GR\n" ++
        hub ++ "grpc.bend as G\n" ++ hub ++ "grpcio.bend as Rpc\n" ++ hub ++ "h2io.bend as H2\n"

def validate_methods(methods: List<&2, M.Method>, +service: String) -> Maybe<&2, String>:
  match methods:
    case Nil{}: None{}
    case Con{M.Method{method, _, _, True{}, _}, _}:
      Some{"client streaming is unsupported by grpcio: " ++ service ++ "/" ++ method}
    case Con{_, rest}: validate_methods(rest, service)

def validate(services: List<&2, M.Service>) -> Maybe<&2, String>:
  match services:
    case Nil{}: None{}
    case Con{M.Service{service, methods}, rest}:
      Maybe.or(&2, String, validate_methods(methods, service), validate(rest))

def result_type(name: String, streamed: Bool) -> String:
  match streamed:
    case False{}: "Result<&2, &2, G.GStatus, " ++ name ++ ">"
    case True{}: "Result<&2, &2, G.GStatus, List<&2, " ++ name ++ ">>"

def cardinality(streamed: Bool) -> String:
  match streamed:
    case False{}: "unary"
    case True{}: "stream"

def wire_path(service: String, method: String) -> String:
  String.quote("/" ++ String.drop(service, 1n) ++ "/" ++ method)

def client(method: M.Method, +service: String) -> String:
  match method:
    case M.Method{+method, input, output, _, +streamed}:
      +req = M.name(input)
      +resp = M.name(output)
      +stem = M.name(service)
      +rpc = M.ident(method)
      "def " ++ stem ++ ".path." ++ rpc ++ "() -> String:\n  " ++ wire_path(service, method) ++ "\n\n" ++
        "def " ++ stem ++ ".call." ++ rpc ++ "(conn: Chan(H2.H2Msg), request: " ++ req ++ ", timeout_ms: U32) ->\n" ++
        "  IO(" ++ result_type(resp, streamed) ++ "):\n" ++
        "  GR.client_" ++ cardinality(streamed) ++ "(~" ++ resp ++ ", ~" ++ resp ++ ".decode, conn, " ++ stem ++
        ".path." ++ rpc ++ "(), " ++ req ++ ".encode_checked(request), timeout_ms)\n\n"

def clients(methods: List<&2, M.Method>, +service: String) -> String:
  match methods:
    case Nil{}: ""
    case Con{m, rest}: client(m, service) ++ clients(rest, service)

def member_type(typed: Bool, input: String, output: String, streamed: Bool) -> String:
  match typed:
    case False{}: ""
    case True{}: ": GR.Context -> " ++ M.name(input) ++ " -> IO(" ++ result_type(M.name(output), streamed) ++ ")"

def members(methods: List<&2, M.Method>, +typed: Bool) -> List<&2, String>:
  match methods:
    case Nil{}: Nil{}
    case Con{M.Method{method, input, output, _, streamed}, rest}:
      label = "handle_" ++ M.ident(method)
      suffix = member_type(typed, input, output, streamed)
      Con{label ++ suffix, members(rest, typed)}

def dispatch_cases(methods: List<&2, M.Method>, +service: String) -> String:
  match methods:
    case Nil{}: "        case _: Rpc.Grpc.finish(sink, G.GStatus{G.Grpc.unimplemented(), \"unknown RPC method\"})\n\n"
    case Con{M.Method{+method, input, output, _, streamed}, rest}:
      +req = M.name(input)
      +resp = M.name(output)
      "        case " ++ wire_path(service, method) ++ ":\n" ++
        "          GR.serve_" ++ cardinality(streamed) ++ "(~" ++ req ++ ", ~" ++ resp ++ ", ~" ++ resp ++
        ".encode_checked, handle_" ++ M.ident(method) ++ ", ctx, " ++ req ++ ".decode(bytes), sink)\n" ++
        dispatch_cases(rest, service)

def service_code(service: M.Service) -> String:
  match service:
    case M.Service{+raw, +methods}:
      +name = M.name(raw)
      +handlers = name ++ ".Handlers"
      clients(methods, raw) ++
        "type " ++ handlers ++ " is Type:\n  " ++ handlers ++ "{" ++ String.join(members(methods, True{}), ", ") ++ "}\n\n" ++
        "def " ++ name ++ ".route(handlers: " ++ handlers ++ ", path: String, bytes: List<&2, U32>, ctx: GR.Context, sink: Rpc.GSink) -> IO(Unit):\n" ++
        "  match handlers:\n    case " ++ handlers ++ "{" ++ String.join(members(methods, False{}), ", ") ++ "}:\n" ++
        "      match path:\n" ++ dispatch_cases(methods, raw) ++
        "def " ++ name ++ ".dispatch(handlers: " ++ handlers ++ ", call: Rpc.GCall) -> IO(Unit):\n" ++
        "  match call:\n" ++
        "    case Rpc.GCall{path, md, bytes, ms, sink}:\n" ++
        "      " ++ name ++ ".route(handlers, path, bytes, GR.Context{md, ms}, sink)\n\n"

def emit(services: List<&2, M.Service>) -> String:
  match services:
    case Nil{}: ""
    case Con{s, rest}: service_code(s) ++ emit(rest)
