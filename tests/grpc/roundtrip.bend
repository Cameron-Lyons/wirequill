import Base
import ./schema.bend as S
import ./grpc_runtime.bend as GR
import 0xc8d18670ba37041507e7f53cc7972ec6/src/grpc.bend as G
import 0xc8d18670ba37041507e7f53cc7972ec6/src/grpcio.bend as Rpc
import 0xc8d18670ba37041507e7f53cc7972ec6/src/h2io.bend as H2
import 0xc8d18670ba37041507e7f53cc7972ec6/src/sys.bend as Sys

def say(ctx: GR.Context, value: S.PB_demo_Value) -> IO(Result<&2, &2, G.GStatus, S.PB_demo_Value>):
  match value:
    case S.PB_demo_Value{13}: IO.pure(Result<&2, &2, G.GStatus, S.PB_demo_Value>, Fail{G.GStatus{7, "denied"}})
    case v: IO.pure(Result<&2, &2, G.GStatus, S.PB_demo_Value>, Done{v})

def list_values(ctx: GR.Context, value: S.PB_demo_Value) -> IO(Result<&2, &2, G.GStatus, List<&2, S.PB_demo_Value>>):
  IO.pure(Result<&2, &2, G.GStatus, List<&2, S.PB_demo_Value>>, Done{[S.PB_demo_Value{1}, value]})

def handle(call: Rpc.GCall) -> IO(Unit):
  S.PB_demo_Echo.dispatch(S.PB_demo_Echo.Handlers{say, list_values}, call)

def check(result: Result<&2, &2, G.GStatus, S.PB_demo_Value>) -> IO(Unit):
  match result:
    case Done{S.PB_demo_Value{42}}: IO.pure(Unit, Unit{})
    case Fail{G.GStatus{code, msg}}: IO.die(Unit, 1, "unary RPC failed: " ++ U32.show(code) ++ " " ++ msg)
    case _: IO.die(Unit, 1, "wrong unary response")

def check_stream(result: Result<&2, &2, G.GStatus, List<&2, S.PB_demo_Value>>) -> IO(Unit):
  match result:
    case Done{[S.PB_demo_Value{1}, S.PB_demo_Value{42}]}: IO.pure(Unit, Unit{})
    case Fail{G.GStatus{code, msg}}: IO.die(Unit, 1, "stream RPC failed: " ++ U32.show(code) ++ " " ++ msg)
    case _: IO.die(Unit, 1, "wrong streaming response")

def denied(result: Result<&2, &2, G.GStatus, S.PB_demo_Value>) -> IO(Unit):
  match result:
    case Fail{G.GStatus{7, "denied"}}: IO.pure(Unit, Unit{})
    case _: IO.die(Unit, 1, "application status lost in transit")

def status_matches(ok: Bool) -> IO(Unit):
  match ok:
    case True{}: IO.pure(Unit, Unit{})
    case False{}: IO.die(Unit, 1, "wrong RPC status")

def check_status(result: Result<&2, &2, G.GStatus, List<&2, U32>>, expected: U32) -> IO(Unit):
  match result:
    case Fail{G.GStatus{code, _}}: status_matches(U32.is_eq(code, expected))
    case Done{_}: IO.die(Unit, 1, "expected RPC error")

def roundtrip(+path: String) -> IO(Unit):
  do IO<Unit>:
    l : Listener <- IO.try(Listener, Sys.Sys.unix_listen(path, 384))
    +calls : Chan(Rpc.GCall) <- Chan.new(Rpc.GCall, 8)
    IO.spawn(Unit, Rpc.Grpc.run(~handle, calls))
    IO.spawn(Unit, Rpc.Grpc.serve(l, calls))
    socket : Socket <- IO.try(Socket, Sys.Sys.unix_connect(path))
    +conn : Chan(H2.H2Msg) <- H2.H2io.client(socket)
    unary : Result<&2, &2, G.GStatus, S.PB_demo_Value> <- S.PB_demo_Echo.call.Say(conn, S.PB_demo_Value{42}, 3000)
    check(unary)
    rejection : Result<&2, &2, G.GStatus, S.PB_demo_Value> <- S.PB_demo_Echo.call.Say(conn, S.PB_demo_Value{13}, 3000)
    denied(rejection)
    stream : Result<&2, &2, G.GStatus, List<&2, S.PB_demo_Value>> <- S.PB_demo_Echo.call.List(conn, S.PB_demo_Value{42}, 3000)
    check_stream(stream)
    malformed : Result<&2, &2, G.GStatus, List<&2, U32>> <- Rpc.Grpc.unary(conn, "/demo.Echo/Say", [128], 3000)
    check_status(malformed, 3)
    missing : Result<&2, &2, G.GStatus, List<&2, U32>> <- Rpc.Grpc.unary(conn, "/demo.Echo/Missing", [], 3000)
    check_status(missing, 12)
    IO.print("gRPC round trip passed")
    IO.exit(0)

def run(args: List<String>) -> IO(Unit):
  match args:
    case [_, path]: roundtrip(path)
    case _: IO.die(Unit, 1, "supply a fresh Unix socket path")

def main() -> IO(Unit):
  IO.bind(List<String>, Unit, IO.args(), run)
