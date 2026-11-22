import Base
import ./schema.bend as S
import ./grpc_runtime.bend as GR
import 0xc8d18670ba37041507e7f53cc7972ec6/src/grpc.bend as G
import 0xc8d18670ba37041507e7f53cc7972ec6/src/grpcio.bend as Rpc
import 0xc8d18670ba37041507e7f53cc7972ec6/src/h2io.bend as H2
import 0xc8d18670ba37041507e7f53cc7972ec6/src/h2.bend as Wire
import 0xc8d18670ba37041507e7f53cc7972ec6/src/sys.bend as Sys

def say(ctx: GR.Context, value: S.PB_demo_Value) -> IO(Result<&2, &2, G.GStatus, S.PB_demo_Value>):
  match value:
    case S.PB_demo_Value{13}: IO.pure(Result<&2, &2, G.GStatus, S.PB_demo_Value>, Fail{G.GStatus{7, "denied"}})
    case v: IO.pure(Result<&2, &2, G.GStatus, S.PB_demo_Value>, Done{v})

def list_values(ctx: GR.Context, value: S.PB_demo_Value) -> IO(Result<&2, &2, G.GStatus, List<&2, S.PB_demo_Value>>):
  IO.pure(Result<&2, &2, G.GStatus, List<&2, S.PB_demo_Value>>, Done{[S.PB_demo_Value{1}, value]})

def sum(values: List<&2, S.PB_demo_Value>, acc: U32) -> U32:
  match values:
    case Nil{}: acc
    case Con{S.PB_demo_Value{v}, rest}: sum(rest, U32.add(v, acc))

def collected(r: GR.Outcome(List<&2, S.PB_demo_Value>)) -> GR.Outcome(S.PB_demo_Value):
  match r:
    case Fail{st}: Fail{st}
    case Done{values}: Done{S.PB_demo_Value{sum(values, 0)}}

def collect_values(ctx: GR.Context, input: IO(GR.Read<S.PB_demo_Value>)) -> IO(GR.Outcome(S.PB_demo_Value)):
  do IO<GR.Outcome(S.PB_demo_Value)>:
    r : GR.Outcome(List<&2, S.PB_demo_Value>) <- GR.all(~S.PB_demo_Value, input)
    return collected(r)

def echo_each(fuel: Nat, item: GR.Read<S.PB_demo_Value>, output: GR.Write<S.PB_demo_Value>) -> IO(Unit):
  match fuel item output:
    case _ _ GR.FailedWrite{_}: IO.pure(Unit, Unit{})
    case _ GR.End{} GR.Write{_, finish}: finish(G.GStatus{0, ""})
    case _ GR.Refused{st} GR.Write{_, finish}: finish(st)
    case 0n _ GR.Write{_, finish}: finish(G.GStatus{8, "test stream limit exceeded"})
    case 1n+f GR.Item{v, next} GR.Write{send, _}:
      do IO<Unit>:
        writer : GR.Write<S.PB_demo_Value> <- send(v)
        event : GR.Read<S.PB_demo_Value> <- next(Unit{})
        echo_each(f, event, writer)

def chat(ctx: GR.Context, input: IO(GR.Read<S.PB_demo_Value>), out: GR.Write<S.PB_demo_Value>) -> IO(Unit):
  IO.bind(GR.Read<S.PB_demo_Value>, Unit, input, e => echo_each(H2.H2io.fuel(), e, out))

def handle(call: GR.Call) -> IO(Unit):
  S.PB_demo_Echo.accept(S.PB_demo_Echo.Handlers{say, list_values, collect_values, chat}, call)

# The client waits for its first reply before it sends the next request.
# A server that buffers until half-close would deadlock here.
def first_response(first: GR.Read<S.PB_demo_Value>, writer: GR.Write<S.PB_demo_Value>) -> IO(GR.Outcome(S.PB_demo_Value)):
  match first:
    case GR.Item{S.PB_demo_Value{1}, next}:
      GR.client_one(~S.PB_demo_Value, ~S.PB_demo_Value, [S.PB_demo_Value{42}], writer, next(Unit{}))
    case GR.Refused{st}: IO.pure(GR.Outcome(S.PB_demo_Value), Fail{st})
    case _: IO.die(GR.Outcome(S.PB_demo_Value), 1, "wrong first duplex response")

def converse(out: GR.Write<S.PB_demo_Value>, input: IO(GR.Read<S.PB_demo_Value>)) -> IO(GR.Outcome(S.PB_demo_Value)):
  match out:
    case GR.FailedWrite{st}: IO.pure(GR.Outcome(S.PB_demo_Value), Fail{st})
    case GR.Write{send, _}:
      do IO<GR.Outcome(S.PB_demo_Value)>:
        writer : GR.Write<S.PB_demo_Value> <- send(S.PB_demo_Value{1})
        first : GR.Read<S.PB_demo_Value> <- input
        first_response(first, writer)

def empty_calls(collected: GR.Outcome(S.PB_demo_Value), messages: GR.Outcome(List<&2, S.PB_demo_Value>)) -> IO(Unit):
  match collected messages:
    case Done{S.PB_demo_Value{0}} Done{Nil{}}: IO.pure(Unit, Unit{})
    case _ _: IO.die(Unit, 1, "empty stream/half-close failed")

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

def large_batch(n: Nat, +value: S.PB_demo_Value) -> List<&2, S.PB_demo_Value>:
  match n:
    case 0n: Nil{}
    case 1n+m: Con{value, large_batch(m, value)}

def check_count(r: GR.Outcome(List<&2, S.PB_demo_Value>)) -> IO(Unit):
  match r:
    case Done{vs}: status_matches(Nat.is_eq(List.length(&2, S.PB_demo_Value, vs), 300n))
    case Fail{_}: IO.die(Unit, 1, "batch failed while requests and replies were in flight")

def fragments(opened: Maybe<&1, H2.SEv>, +conn: Chan(H2.H2Msg), +events: Chan(H2.SEv)) -> IO(Unit):
  match opened:
    case Some{H2.SOpened{+sid}}:
      do IO<Unit>:
        # A frame header spans two DATA chunks, and its payload shares a
        # chunk with the next empty and nonempty protobuf messages.
        Rpc.Grpc.put(conn, sid, Wire.CData{[0, 0], False{}})
        Rpc.Grpc.put(conn, sid, Wire.CData{[0, 0, 2, 8, 12, 0, 0, 0, 0, 0, 0, 0, 0, 0, 2, 8, 30], True{}})
        e : Maybe<&1, H2.SEv> <- Chan.recv(H2.SEv, events)
        wire : Result<&2, &2, String, H2.H2Resp> <- H2.H2io.collect(H2.H2io.fuel(), H2.H2io.fuel(),
          H2.CEv{H2.H2Resp{Nil{}, Nil{}, Nil{}}, e}, events)
        check(Result.bind(&2, &2, G.GStatus, List<&2, U32>, S.PB_demo_Value, Rpc.Grpc.single(Rpc.Grpc.answer(wire)),
          bytes => GR.response(S.PB_demo_Value, S.PB_demo_Value.decode(bytes))))
    case _: IO.die(Unit, 1, "could not open fragmented request")

def raw_requests(+conn: Chan(H2.H2Msg)) -> IO(Unit):
  do IO<Unit>:
    +events : Chan(H2.SEv) <- Chan.new(H2.SEv, 16)
    sent : Result<&1, &1, H2.H2Msg, Unit> <- Chan.send(H2.H2Msg, conn,
      H2.MOpen{G.Grpc.call_headers(S.PB_demo_Echo.path.Collect(), 3000), False{}, events})
    e : Maybe<&1, H2.SEv> <- Chan.recv(H2.SEv, events)
    fragments(e, conn, events)
    extra : Result<&2, &2, String, H2.H2Resp> <- H2.H2io.call(conn, G.Grpc.call_headers(S.PB_demo_Echo.path.Say(), 3000),
      G.Grpc.frames([[], []]))
    check_status(Rpc.Grpc.single(Rpc.Grpc.answer(extra)), 3)
    invalid : Result<&2, &2, String, H2.H2Resp> <- H2.H2io.call(conn, G.Grpc.call_headers(S.PB_demo_Echo.path.Collect(), 3000),
      G.Grpc.frames([[], [128]]))
    check_status(Rpc.Grpc.single(Rpc.Grpc.answer(invalid)), 3)
    short : Result<&2, &2, String, H2.H2Resp> <- H2.H2io.call(conn, G.Grpc.call_headers(S.PB_demo_Echo.path.Collect(), 3000), [0, 0])
    check_status(Rpc.Grpc.single(Rpc.Grpc.answer(short)), 13)

def stalled(out: GR.Write<S.PB_demo_Value>, input: IO(GR.Read<S.PB_demo_Value>)) -> IO(GR.Outcome(Unit)):
  do IO<GR.Outcome(Unit)>:
    IO.sleep(100)
    return Done{Unit{}}

def deadline(r: GR.Outcome(Unit)) -> IO(Unit):
  match r:
    case Fail{G.GStatus{4, _}}: IO.pure(Unit, Unit{})
    case _: IO.die(Unit, 1, "missing deadline status")

# The handler waits for the client's acknowledgement before producing its
# second value. Buffering on either side would keep the gate closed.
def gated_list(gate: Chan(Unit), ctx: GR.Context, value: S.PB_demo_Value, output: GR.Write<S.PB_demo_Value>) -> IO(Unit):
  match output:
    case GR.FailedWrite{_}: IO.pure(Unit, Unit{})
    case GR.Write{send, _}:
      do IO<Unit>:
        next : GR.Write<S.PB_demo_Value> <- send(S.PB_demo_Value{1})
        ack : Maybe<&1, Unit> <- Chan.recv(Unit, gate)
        GR.write_list(~S.PB_demo_Value, Done{[value]}, next)

def streaming_handler(gate: Chan(Unit), call: GR.Call) -> IO(Unit):
  S.PB_demo_Echo.accept_streaming(S.PB_demo_Echo.StreamingHandlers{say, gated_list(gate), collect_values, chat}, call)

def streaming_request(req: Maybe<&1, H2.H2Req>, gate: Chan(Unit)) -> IO(Unit):
  match req:
    case None{}: IO.die(Unit, 1, "streaming server closed")
    case Some{r}: GR.attend(call => streaming_handler(gate, call), r)

def acknowledge(first: GR.Read<S.PB_demo_Value>, gate: Chan(Unit)) -> IO(GR.Outcome(S.PB_demo_Value)):
  match first:
    case GR.Item{S.PB_demo_Value{1}, next}:
      do IO<GR.Outcome(S.PB_demo_Value)>:
        sent : Result<&1, &1, Unit, Unit> <- Chan.send(Unit, gate, Unit{})
        tail : GR.Read<S.PB_demo_Value> <- next(Unit{})
        GR.single(~S.PB_demo_Value, tail, G.GStatus{13, "expected one more reply"})
    case GR.Refused{st}: IO.pure(GR.Outcome(S.PB_demo_Value), Fail{st})
    case _: IO.die(GR.Outcome(S.PB_demo_Value), 1, "wrong first server-streamed response")

def live_server_stream(+path: String) -> IO(Unit):
  do IO<Unit>:
    +gate : Chan(Unit) <- Chan.new(Unit, 1)
    +requests : Chan(H2.H2Req) <- Chan.new(H2.H2Req, 1)
    listener : Listener <- IO.try(Listener, Sys.Sys.unix_listen(path, 384))
    IO.spawn(Unit, H2.H2io.serve(listener, requests))
    IO.spawn(Unit, IO.bind(Maybe<&1, H2.H2Req>, Unit, Chan.recv(H2.H2Req, requests), req => streaming_request(req, gate)))
    socket : Socket <- IO.try(Socket, Sys.Sys.unix_connect(path))
    conn : Chan(H2.H2Msg) <- H2.H2io.client(socket)
    r : GR.Outcome(S.PB_demo_Value) <- S.PB_demo_Echo.stream.List(~S.PB_demo_Value, conn, S.PB_demo_Value{42},
      input => IO.bind(GR.Read<S.PB_demo_Value>, GR.Outcome(S.PB_demo_Value), input, first => acknowledge(first, gate)), 3000)
    check(r)

def roundtrip(+path: String) -> IO(Unit):
  do IO<Unit>:
    l : Listener <- IO.try(Listener, Sys.Sys.unix_listen(path, 384))
    IO.spawn(Unit, GR.serve(~handle, l))
    socket : Socket <- IO.try(Socket, Sys.Sys.unix_connect(path))
    +conn : Chan(H2.H2Msg) <- H2.H2io.client(socket)
    unary : Result<&2, &2, G.GStatus, S.PB_demo_Value> <- S.PB_demo_Echo.call.Say(conn, S.PB_demo_Value{42}, 3000)
    check(unary)
    rejection : Result<&2, &2, G.GStatus, S.PB_demo_Value> <- S.PB_demo_Echo.call.Say(conn, S.PB_demo_Value{13}, 3000)
    denied(rejection)
    stream : Result<&2, &2, G.GStatus, List<&2, S.PB_demo_Value>> <- S.PB_demo_Echo.call.List(conn, S.PB_demo_Value{42}, 3000)
    check_stream(stream)
    live_server_stream(path ++ ".stream")
    upload : GR.Outcome(S.PB_demo_Value) <- S.PB_demo_Echo.call.Collect(conn, [S.PB_demo_Value{12}, S.PB_demo_Value{30}], 3000)
    check(upload)
    bidirectional : GR.Outcome(S.PB_demo_Value) <- S.PB_demo_Echo.exchange.Chat(~S.PB_demo_Value, conn, converse, 3000)
    check(bidirectional)
    batch : GR.Outcome(List<&2, S.PB_demo_Value>) <- S.PB_demo_Echo.call.Chat(conn, [S.PB_demo_Value{1}, S.PB_demo_Value{42}], 0)
    check_stream(batch)
    no_input : GR.Outcome(S.PB_demo_Value) <- S.PB_demo_Echo.call.Collect(conn, Nil{}, 3000)
    no_output : GR.Outcome(List<&2, S.PB_demo_Value>) <- S.PB_demo_Echo.call.Chat(conn, Nil{}, 3000)
    empty_calls(no_input, no_output)
    over_buffer : GR.Outcome(List<&2, S.PB_demo_Value>) <- S.PB_demo_Echo.call.Chat(conn, large_batch(300n, S.PB_demo_Value{7}), 5000)
    check_count(over_buffer)
    raw_requests(conn)
    late : GR.Outcome(Unit) <- S.PB_demo_Echo.exchange.Chat(~Unit, conn, stalled, 25)
    deadline(late)
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
