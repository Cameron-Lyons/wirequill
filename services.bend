import Base
import ./model.bend as M

def imports(services: List<&2, M.Service>) -> String:
  match services:
    case Nil{}: ""
    case Con{_, _}:
      +hub = {"import 0xc8d18670ba37041507e7f53cc7972ec6/src/" : String}
      "import ./grpc_runtime.bend as GR\n" ++
        hub ++ "grpc.bend as G\n" ++ hub ++ "grpcio.bend as Rpc\n" ++ hub ++ "h2io.bend as H2\n"

def payload(name: String, streamed: Bool) -> String:
  match streamed:
    case False{}: name
    case True{}: "List<&2, " ++ name ++ ">"

def wire_path(service: String, method: String) -> String:
  String.quote("/" ++ String.drop(service, 1n) ++ "/" ++ method)

def batch(streamed: Bool) -> String:
  match streamed:
    case False{}: "one"
    case True{}: "many"

def client_body(+req: String, +resp: String, +service: String, +method: String, upload: Bool, +streamed: Bool) -> String:
  match upload streamed:
    case False{} False{}:
      "  GR.client_unary(~" ++ resp ++ ", ~" ++ resp ++ ".decode, conn, " ++ service ++
        ".path." ++ method ++ "(), " ++ req ++ ".encode_checked(request), timeout_ms)\n\n"
    case False{} True{}:
      "  " ++ service ++ ".stream." ++ method ++ "(~List<&2, " ++ resp ++ ">, conn, request, " ++
        "input => GR.all(~" ++ resp ++ ", input), timeout_ms)\n\n"
    case True{} many:
      "  " ++ service ++ ".exchange." ++ method ++ "(~" ++ payload(resp, many) ++ ", conn, " ++
        "out => input => GR.client_" ++ batch(many) ++ "(~" ++ req ++ ", ~" ++ resp ++ ", request, out, input), timeout_ms)\n\n"

def stream_client(+req: String, +resp: String, +service: String, +method: String, upload: Bool, streamed: Bool) -> String:
  match upload streamed:
    case False{} False{}: ""
    case False{} True{}:
      "def " ++ service ++ ".stream." ++ method ++ "(~A: Data, conn: Chan(H2.H2Msg), request: " ++ req ++ ",\n" ++
        "  consume: IO(GR.Read<" ++ resp ++ ">) -> IO(GR.Outcome(A)), timeout_ms: U32) -> IO(GR.Outcome(A)):\n" ++
        "  GR.exchange(~" ++ req ++ ", ~" ++ resp ++ ", ~A, ~" ++ req ++ ".encode_checked, ~" ++ resp ++ ".decode, conn, " ++
        service ++ ".path." ++ method ++ "(), out => input => GR.response_stream(~" ++ req ++ ", ~A, request, out, consume(input)), timeout_ms)\n\n"
    case True{} _:
      "def " ++ service ++ ".exchange." ++ method ++ "(~A: Data, conn: Chan(H2.H2Msg),\n" ++
        "  interact: GR.Write<" ++ req ++ "> -> IO(GR.Read<" ++ resp ++ ">) -> IO(GR.Outcome(A)), timeout_ms: U32) -> IO(GR.Outcome(A)):\n" ++
        "  GR.exchange(~" ++ req ++ ", ~" ++ resp ++ ", ~A, ~" ++ req ++ ".encode_checked, ~" ++ resp ++ ".decode, conn, " ++
        service ++ ".path." ++ method ++ "(), interact, timeout_ms)\n\n"

def client(method: M.Method, +service: String) -> String:
  match method:
    case M.Method{+method, input, output, +upload, +streamed}:
      +req = M.name(input)
      +resp = M.name(output)
      +stem = M.name(service)
      +rpc = M.ident(method)
      "def " ++ stem ++ ".path." ++ rpc ++ "() -> String:\n  " ++ wire_path(service, method) ++ "\n\n" ++
        stream_client(req, resp, stem, rpc, upload, streamed) ++
        "def " ++ stem ++ ".call." ++ rpc ++ "(conn: Chan(H2.H2Msg), request: " ++ payload(req, upload) ++ ", timeout_ms: U32) ->\n" ++
        "  IO(GR.Outcome(" ++ payload(resp, streamed) ++ ")):\n" ++ client_body(req, resp, stem, rpc, upload, streamed)

def clients(methods: List<&2, M.Method>, +service: String) -> String:
  match methods:
    case Nil{}: ""
    case Con{m, rest}: client(m, service) ++ clients(rest, service)

type MemberStyle is Data:
  Label{}
  Buffered{}
  Streaming{}
  Adapter{}

def member(+style: MemberStyle, +label: String, +req: String, +resp: String, upload: Bool, streamed: Bool) -> String:
  match style upload streamed:
    case Label{} _ _: label
    case Adapter{} False{} True{}:
      "ctx => value => out => GR.list_handler(~" ++ resp ++ ", " ++ label ++ "(ctx, value), out)"
    case Adapter{} _ _: label
    case Streaming{} False{} True{}:
      label ++ ": GR.Context -> " ++ req ++ " -> GR.Write<" ++ resp ++ "> -> IO(Unit)"
    case _ False{} many: label ++ ": GR.Context -> " ++ req ++ " -> IO(GR.Outcome(" ++ payload(resp, many) ++ "))"
    case _ True{} False{}: label ++ ": GR.Context -> IO(GR.Read<" ++ req ++ ">) -> IO(GR.Outcome(" ++ resp ++ "))"
    case _ True{} True{}: label ++ ": GR.Context -> IO(GR.Read<" ++ req ++ ">) -> GR.Write<" ++ resp ++ "> -> IO(Unit)"

def members(methods: List<&2, M.Method>, +style: MemberStyle) -> List<&2, String>:
  match methods:
    case Nil{}: Nil{}
    case Con{M.Method{method, input, output, upload, streamed}, rest}:
      value = member(style, "handle_" ++ M.ident(method), M.name(input), M.name(output), upload, streamed)
      Con{value, members(rest, style)}

def has_server_stream(methods: List<&2, M.Method>) -> Bool:
  match methods:
    case Nil{}: False{}
    case Con{M.Method{_, _, _, False{}, True{}}, _}: True{}
    case Con{_, rest}: has_server_stream(rest)

def invoke(+req: String, +resp: String, +handle: String, upload: Bool, streamed: Bool) -> String:
  match upload streamed:
    case False{} False{}:
      "GR.one_request(~" ++ req ++ ", incoming, value => GR.serve_unary(~" ++ req ++ ", ~" ++ resp ++
        ", ~" ++ resp ++ ".encode_checked, " ++ handle ++ ", ctx, Some{value}, sink), sink)"
    case False{} True{}:
      "GR.one_request(~" ++ req ++ ", incoming, value => " ++ handle ++ "(ctx, value, GR.writer(~" ++ resp ++
        ", ~" ++ resp ++ ".encode_checked, GR.Reply{sink})), sink)"
    case True{} False{}:
      "IO.bind(GR.Outcome(" ++ resp ++ "), Unit, " ++ handle ++ "(ctx, incoming),\n" ++
        "            r => GR.unary_result(~" ++ resp ++ ", ~" ++ resp ++ ".encode_checked, r, sink))"
    case True{} True{}:
      handle ++ "(ctx, incoming, GR.writer(~" ++ resp ++ ", ~" ++ resp ++ ".encode_checked, GR.Reply{sink}))"

def dispatch_cases(methods: List<&2, M.Method>, +service: String) -> String:
  match methods:
    case Nil{}: "        case _: Rpc.Grpc.finish(sink, G.GStatus{G.Grpc.unimplemented(), \"unknown RPC method\"})\n\n"
    case Con{M.Method{+method, input, output, upload, streamed}, rest}:
      +req = M.name(input)
      "        case " ++ wire_path(service, method) ++ ":\n" ++
        "          incoming = GR.read(~" ++ req ++ ", ~" ++ req ++ ".decode, cursor, G.GStatus{3, \"invalid protobuf request\"})\n          " ++
        invoke(req, M.name(output), "handle_" ++ M.ident(method), upload, streamed) ++ "\n" ++ dispatch_cases(rest, service)

def handler_type(+name: String, methods: List<&2, M.Method>, style: MemberStyle) -> String:
  "type " ++ name ++ " is Type:\n  " ++ name ++ "{" ++ String.join(members(methods, style), ", ") ++ "}\n\n"

def route_source(+route: String, +handlers: String, +methods: List<&2, M.Method>, service: String) -> String:
  "def " ++ route ++ "(handlers: " ++ handlers ++ ", path: String, cursor: GR.Cursor, ctx: GR.Context, +sink: Rpc.GSink) -> IO(Unit):\n" ++
    "  match handlers:\n    case " ++ handlers ++ "{" ++ String.join(members(methods, Label{}), ", ") ++ "}:\n" ++
    "      match path:\n" ++ dispatch_cases(methods, service)

def accept_source(entry: String, handlers: String, route: String) -> String:
  "def " ++ entry ++ "(handlers: " ++ handlers ++ ", call: GR.Call) -> IO(Unit):\n" ++
    "  match call:\n    case GR.Call{path, ctx, input, sink}: " ++ route ++ "(handlers, path, input, ctx, sink)\n\n"

def server_routes(+name: String, +methods: List<&2, M.Method>, service: String, has_stream: Bool) -> String:
  match has_stream:
    case False{}: route_source(name ++ ".route_stream", name ++ ".Handlers", methods, service)
    case True{}:
      +live = name ++ ".StreamingHandlers"
      +route = name ++ ".route_streaming"
      handler_type(live, methods, Streaming{}) ++ route_source(route, live, methods, service) ++
        accept_source(name ++ ".accept_streaming", live, route) ++
        "def " ++ name ++ ".route_stream(handlers: " ++ name ++ ".Handlers, path: String, cursor: GR.Cursor, ctx: GR.Context, sink: Rpc.GSink) -> IO(Unit):\n" ++
        "  match handlers:\n    case " ++ name ++ ".Handlers{" ++ String.join(members(methods, Label{}), ", ") ++ "}:\n" ++
        "      " ++ route ++ "(" ++ live ++ "{" ++ String.join(members(methods, Adapter{}), ", ") ++ "}, path, cursor, ctx, sink)\n\n"

def service_code(service: M.Service) -> String:
  match service:
    case M.Service{+raw, +methods}:
      +name = M.name(raw)
      +handlers = name ++ ".Handlers"
      clients(methods, raw) ++ handler_type(handlers, methods, Buffered{}) ++
        server_routes(name, methods, raw, has_server_stream(methods)) ++
        accept_source(name ++ ".accept", handlers, name ++ ".route_stream") ++
        "def " ++ name ++ ".route(handlers: " ++ handlers ++ ", path: String, bytes: List<&2, U32>, ctx: GR.Context, sink: Rpc.GSink) -> IO(Unit):\n" ++
        "  " ++ name ++ ".route_stream(handlers, path, GR.single_cursor(bytes), ctx, sink)\n\n" ++
        "def " ++ name ++ ".dispatch(handlers: " ++ handlers ++ ", call: Rpc.GCall) -> IO(Unit):\n" ++
        "  match call:\n    case Rpc.GCall{path, md, bytes, ms, sink}: " ++ name ++ ".route(handlers, path, bytes, GR.Context{md, ms}, sink)\n\n"

def emit_chunks(services: List<&2, M.Service>) -> List<(Unit -> String)>:
  match services:
    case Nil{}: Nil{}
    case Con{s, rest}: Con{u => service_code(s), emit_chunks(rest)}
