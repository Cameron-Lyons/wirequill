import Base
import 0xc8d18670ba37041507e7f53cc7972ec6/src/grpc.bend as G
import 0xc8d18670ba37041507e7f53cc7972ec6/src/grpcio.bend as Rpc
import 0xc8d18670ba37041507e7f53cc7972ec6/src/h2io.bend as H2
import 0xc8d18670ba37041507e7f53cc7972ec6/src/h2.bend as Wire
import 0xc8d18670ba37041507e7f53cc7972ec6/src/http.bend as Http

# Request metadata and the timeout (milliseconds, zero means no deadline).
type Context is Data:
  Context{metadata: List<&2, Http.Header>, timeout_ms: U32}

def response(-A: Data, parsed: Maybe<&2, A>) -> Result<&2, &2, G.GStatus, A>:
  match parsed:
    case Some{value}: Done{value}
    case None{}: Fail{G.GStatus{G.Grpc.internal(), "invalid protobuf response"}}

def responses(~A: Data, ~decode: List<&2, U32> -> Maybe<&2, A>, messages: List<&2, List<&2, U32>>) ->
  Result<&2, &2, G.GStatus, List<&2, A>>:
  match messages:
    case Nil{}: Done{Nil{}}
    case Con{msg, rest}:
      do Result<&2, &2, G.GStatus, List<&2, A>>:
        value : A <- response(A, decode(msg))
        tail : List<&2, A> <- responses(~A, ~decode, rest)
        return Con{value, tail}

def client_unary(~A: Data, ~decode: List<&2, U32> -> Maybe<&2, A>, conn: Chan(H2.H2Msg),
  path: String, request: Maybe<&2, List<&2, U32>>, ms: U32) -> IO(Result<&2, &2, G.GStatus, A>):
  match request:
    case None{}: IO.pure(Result<&2, &2, G.GStatus, A>, Fail{G.GStatus{G.Grpc.invalid_argument(), "invalid protobuf request"}})
    case Some{bytes}:
      do IO<Result<&2, &2, G.GStatus, A>>:
        wire : Result<&2, &2, G.GStatus, List<&2, U32>> <- Rpc.Grpc.unary(conn, path, bytes, ms)
        return Result.bind(&2, &2, G.GStatus, List<&2, U32>, A, wire, msg => response(A, decode(msg)))

def client_stream(~A: Data, ~decode: List<&2, U32> -> Maybe<&2, A>, conn: Chan(H2.H2Msg),
  path: String, request: Maybe<&2, List<&2, U32>>, ms: U32) -> IO(Result<&2, &2, G.GStatus, List<&2, A>>):
  match request:
    case None{}: IO.pure(Result<&2, &2, G.GStatus, List<&2, A>>, Fail{G.GStatus{G.Grpc.invalid_argument(), "invalid protobuf request"}})
    case Some{bytes}:
      do IO<Result<&2, &2, G.GStatus, List<&2, A>>>:
        wire : Result<&2, &2, G.GStatus, List<&2, List<&2, U32>>> <- Rpc.Grpc.stream(conn, path, bytes, ms)
        return Result.bind(&2, &2, G.GStatus, List<&2, List<&2, U32>>, List<&2, A>, wire,
          messages => responses(~A, ~decode, messages))

def encoded(bytes: Maybe<&2, List<&2, U32>>) -> Result<&2, &2, G.GStatus, List<&2, U32>>:
  match bytes:
    case None{}: Fail{G.GStatus{G.Grpc.internal(), "invalid protobuf response"}}
    case Some{value}: Done{value}

def serve_unary(~A: Data, ~B: Data, ~encode: B -> Maybe<&2, List<&2, U32>>,
  handle: Context -> A -> IO(Result<&2, &2, G.GStatus, B>),
  ctx: Context, req: Maybe<&2, A>, sink: Rpc.GSink) -> IO(Unit):
  match req:
    case None{}: Rpc.Grpc.finish(sink, G.GStatus{G.Grpc.invalid_argument(), "invalid protobuf request"})
    case Some{value}:
      do IO<Unit>:
        answer : Result<&2, &2, G.GStatus, B> <- handle(ctx, value)
        Rpc.Grpc.reply(sink, Result.bind(&2, &2, G.GStatus, B, List<&2, U32>, answer, value => encoded(encode(value))))

def send_one(bytes: Maybe<&2, List<&2, U32>>, sink: Rpc.GSink) -> IO(Maybe<&2, Rpc.GSink>):
  match bytes:
    case None{}:
      do IO<Maybe<&2, Rpc.GSink>>:
        Rpc.Grpc.finish(sink, G.GStatus{G.Grpc.internal(), "invalid protobuf response"})
        return None{}
    case Some{msg}:
      do IO<Maybe<&2, Rpc.GSink>>:
        next : Rpc.GSink <- Rpc.Grpc.send(sink, msg)
        return Some{next}

def send_messages(~A: Data, ~encode: A -> Maybe<&2, List<&2, U32>>, messages: List<&2, A>, sink: Maybe<&2, Rpc.GSink>) -> IO(Unit):
  match messages sink:
    case _ None{}: IO.pure(Unit, Unit{})
    case Nil{} Some{k}: Rpc.Grpc.finish(k, G.GStatus{G.Grpc.ok(), ""})
    case Con{value, rest} Some{k}:
      do IO<Unit>:
        next : Maybe<&2, Rpc.GSink> <- send_one(encode(value), k)
        send_messages(~A, ~encode, rest, next)

def stream_reply(~A: Data, ~encode: A -> Maybe<&2, List<&2, U32>>,
  reply: Result<&2, &2, G.GStatus, List<&2, A>>, sink: Rpc.GSink) -> IO(Unit):
  match reply:
    case Fail{status}: Rpc.Grpc.finish(sink, status)
    case Done{messages}: send_messages(~A, ~encode, messages, Some{sink})

def serve_stream(~A: Data, ~B: Data, ~encode: B -> Maybe<&2, List<&2, U32>>,
  handle: Context -> A -> IO(Result<&2, &2, G.GStatus, List<&2, B>>),
  ctx: Context, req: Maybe<&2, A>, sink: Rpc.GSink) -> IO(Unit):
  match req:
    case None{}: Rpc.Grpc.finish(sink, G.GStatus{G.Grpc.invalid_argument(), "invalid protobuf request"})
    case Some{value}:
      do IO<Unit>:
        answer : Result<&2, &2, G.GStatus, List<&2, B>> <- handle(ctx, value)
        stream_reply(~B, ~encode, answer, sink)

# A typed stream exposes one message at a time. The continuation retains
# partial frames and unread bytes, including additional messages in one DATA.
type Read<-A: Data> is Type:
  Item{value: A, next: Unit -> IO(Read<A>)}
  End{}
  Refused{status: G.GStatus}

type Source is Data:
  Source{events: Chan(H2.SEv), response: Bool}
  Closed{status: G.GStatus}

type Cursor is Data:
  Cursor{source: Source, part: Cut}

type Cut is Data:
  Need{decoder: G.GRd}
  Found{message: List<&2, U32>, rest: List<&2, U32>}
  BadFrame{status: G.GStatus}

def cut(bs: List<&2, U32>, step: G.GStep) -> Cut:
  match bs step:
    case rest G.GStep{_, Some{message}}: Found{message, rest}
    case _ G.GStep{G.GBad{st}, _}: BadFrame{st}
    case Nil{} G.GStep{rd, None{}}: Need{rd}
    case Con{b, t} G.GStep{rd, None{}}: cut(t, G.Grpc.rd_step(rd, b))

def ready(source: Source) -> Cursor:
  Cursor{source, Need{G.GHead{0, Nil{}}}}

def single_cursor(bytes: List<&2, U32>) -> Cursor:
  Cursor{Closed{G.GStatus{0, ""}}, Found{bytes, Nil{}}}

def after_data(+events: Chan(H2.SEv), response_side: Bool, ended: Bool) -> Source:
  match response_side ended:
    case _ False{}: Source{events, response_side}
    case False{} True{}: Closed{G.GStatus{0, ""}}
    case True{} True{}: Closed{G.GStatus{G.Grpc.unknown(), "missing gRPC trailers"}}

def after_headers(+events: Chan(H2.SEv), response_side: Bool, headers: List<&2, Http.Header>, ended: Bool) -> Source:
  match response_side ended:
    case False{} fin: after_data(events, False{}, fin)
    case True{} True{}: Closed{G.Grpc.status_of(headers)}
    case True{} False{}: Source{events, True{}}

def http_response(headers: List<&2, Http.Header>, +events: Chan(H2.SEv), response_side: Bool, ended: Bool,
  code: Maybe<&2, String>) -> Source:
  match response_side code:
    case True{} Some{"200"}: after_headers(events, True{}, headers, ended)
    case True{} Some{status}: Closed{Rpc.Grpc.http_status(status)}
    case side _: after_headers(events, side, headers, ended)

def feed(+events: Chan(H2.SEv), +side: Bool, rd: G.GRd, event: Maybe<&1, H2.SEv>) -> Cursor:
  match event:
    case Some{H2.SGot{Wire.EvData{_, bytes, fin}}}: Cursor{after_data(events, side, fin), cut(bytes, G.GStep{rd, None{}})}
    case Some{H2.SGot{Wire.EvHeaders{_, +hs, fin}}}:
      Cursor{http_response(hs, events, side, fin, G.Grpc.hdr(hs, ":status")), Need{rd}}
    case Some{H2.SGot{Wire.EvRst{_, code}}}: Cursor{Closed{G.GStatus{14, "stream reset: " ++ U32.show(code)}}, Need{rd}}
    case Some{H2.SGone{why}}: Cursor{Closed{G.GStatus{14, why}}, Need{rd}}
    case None{}: Cursor{Closed{G.GStatus{14, "connection closed"}}, Need{rd}}
    case _: Cursor{Source{events, side}, Need{rd}}

def finish_read(-A: Data, st: G.GStatus, rd: G.GRd) -> Read<A>:
  match st rd:
    case G.GStatus{0, _} G.GHead{0, _}: End{}
    case G.GStatus{0, _} _: Refused{G.GStatus{13, "stream ended inside a message"}}
    case status _: Refused{status}

def item(-A: Data, x: Maybe<&2, A>, next: Unit -> IO(Read<A>), bad: G.GStatus) -> Read<A>:
  match x:
    case Some{v}: Item{v, next}
    case None{}: Refused{bad}

def reading(~A: Data, ~decode: List<&2, U32> -> Maybe<&2, A>, fuel: Nat, cursor: Cursor, +bad: G.GStatus) -> IO(Read<A>):
  match fuel cursor:
    case 0n _: IO.pure(Read<A>, Refused{G.GStatus{8, "stream limit exceeded"}})
    case 1n+f Cursor{_, BadFrame{st}}: IO.pure(Read<A>, Refused{st})
    case 1n+f Cursor{source, Found{message, rest}}:
      IO.pure(Read<A>, item(A, decode(message), u => reading(~A, ~decode, f,
        Cursor{source, cut(rest, G.GStep{G.GHead{0, Nil{}}, None{}})}, bad), bad))
    case 1n+f Cursor{Closed{st}, Need{rd}}: IO.pure(Read<A>, finish_read(A, st, rd))
    case 1n+f Cursor{Source{+events, +side}, Need{rd}}:
      do IO<Read<A>>:
        event : Maybe<&1, H2.SEv> <- Chan.recv(H2.SEv, events)
        reading(~A, ~decode, f, feed(events, side, rd, event), bad)

def read(~A: Data, ~decode: List<&2, U32> -> Maybe<&2, A>, cursor: Cursor, bad: G.GStatus) -> IO(Read<A>):
  reading(~A, ~decode, H2.H2io.fuel(), cursor, bad)

# The sender returned by send carries the header state for the next write.
type Write<-A: Data> is Type:
  Write{send: A -> IO(Write<A>), finish: G.GStatus -> IO(Unit)}
  FailedWrite{status: G.GStatus}

type Destination is Data:
  Request{sid: U32, conn: Chan(H2.H2Msg)}
  Reply{sink: Rpc.GSink}

def close_request(+sid: U32, +conn: Chan(H2.H2Msg), status: G.GStatus) -> IO(Unit):
  match status:
    case G.GStatus{0, _}: Rpc.Grpc.put(conn, sid, Wire.CData{Nil{}, True{}})
    case _:
      do IO<Unit>:
        r : Result<&1, &1, H2.H2Msg, Unit> <- Chan.send(H2.H2Msg, conn, H2.MReset{sid, Wire.H2.cancel()})
        return Unit{}

def finish(dest: Destination, status: G.GStatus) -> IO(Unit):
  match dest:
    case Request{sid, conn}: close_request(sid, conn, status)
    case Reply{sink}: Rpc.Grpc.finish(sink, status)

def queued(dest: Destination, result: Result<&1, &1, H2.H2Msg, Unit>) -> Result<&2, &2, G.GStatus, Destination>:
  match result:
    case Done{_}: Done{dest}
    case Fail{_}: Fail{G.GStatus{14, "connection closed"}}

def put(+dest: Destination, bytes: Maybe<&2, List<&2, U32>>) -> IO(Result<&2, &2, G.GStatus, Destination>):
  match dest bytes:
    case Reply{k} Some{msg}:
      do IO<Result<&2, &2, G.GStatus, Destination>>:
        next : Rpc.GSink <- Rpc.Grpc.send(k, msg)
        return Done{Reply{next}}
    case Request{sid, conn} Some{msg}:
      do IO<Result<&2, &2, G.GStatus, Destination>>:
        sent : Result<&1, &1, H2.H2Msg, Unit> <- Chan.send(H2.H2Msg, conn, H2.MSend{sid, Wire.CData{G.Grpc.frame(msg), False{}}})
        return queued(dest, sent)
    case Reply{k} None{}:
      do IO<Result<&2, &2, G.GStatus, Destination>>:
        +st : G.GStatus = G.GStatus{13, "invalid protobuf response"}
        Rpc.Grpc.finish(k, st)
        return Fail{st}
    case Request{sid, conn} None{}:
      do IO<Result<&2, &2, G.GStatus, Destination>>:
        +st : G.GStatus = G.GStatus{3, "invalid protobuf request"}
        close_request(sid, conn, st)
        return Fail{st}

def writing(~A: Data, ~encode: A -> Maybe<&2, List<&2, U32>>, fuel: Nat, result: Result<&2, &2, G.GStatus, Destination>) -> Write<A>:
  match fuel result:
    case _ Fail{st}: FailedWrite{st}
    case 0n Done{dest}: FailedWrite{G.GStatus{8, "stream limit exceeded"}}
    case 1n+f Done{+dest}:
      Write{value => IO.bind(Result<&2, &2, G.GStatus, Destination>, Write<A>, put(dest, encode(value)),
          r => IO.pure(Write<A>, writing(~A, ~encode, f, r))), st => finish(dest, st)}

def writer(~A: Data, ~encode: A -> Maybe<&2, List<&2, U32>>, dest: Destination) -> Write<A>:
  writing(~A, ~encode, H2.H2io.fuel(), Done{dest})

def Outcome(-A: Data) -> Data:
  Result<&2, &2, G.GStatus, A>

def collect(~A: Data, fuel: Nat, event: Read<A>, acc: List<&2, A>) -> IO(Outcome(List<&2, A>)):
  match fuel event:
    case _ End{}: IO.pure(Outcome(List<&2, A>), Done{List.reverse(&2, A, acc)})
    case _ Refused{st}: IO.pure(Outcome(List<&2, A>), Fail{st})
    case 0n Item{_, _}: IO.pure(Outcome(List<&2, A>), Fail{G.GStatus{8, "stream limit exceeded"}})
    case 1n+f Item{x, next}:
      do IO<Outcome(List<&2, A>)>:
        e : Read<A> <- next(Unit{})
        collect(~A, f, e, Con{x, acc})

def all(~A: Data, input: IO(Read<A>)) -> IO(Outcome(List<&2, A>)):
  IO.bind(Read<A>, Outcome(List<&2, A>), input, e => collect(~A, H2.H2io.fuel(), e, Nil{}))

def single_end(-A: Data, value: A, end: Read<A>, bad: G.GStatus) -> Outcome(A):
  match end:
    case End{}: Done{value}
    case Refused{st}: Fail{st}
    case Item{_, _}: Fail{bad}

def single(~A: Data, first: Read<A>, +bad: G.GStatus) -> IO(Outcome(A)):
  match first:
    case End{}: IO.pure(Outcome(A), Fail{bad})
    case Refused{st}: IO.pure(Outcome(A), Fail{st})
    case Item{x, next}:
      do IO<Outcome(A)>:
        e : Read<A> <- next(Unit{})
        return single_end(A, x, e, bad)

def send_all(~A: Data, xs: List<&2, A>, out: Write<A>) -> IO(Outcome(Unit)):
  match xs out:
    case _ FailedWrite{st}: IO.pure(Outcome(Unit), Fail{st})
    case Nil{} Write{_, close}:
      do IO<Outcome(Unit)>:
        close(G.GStatus{0, ""})
        return Done{Unit{}}
    case Con{x, rest} Write{send, _}:
      do IO<Outcome(Unit)>:
        next : Write<A> <- send(x)
        send_all(~A, rest, next)

def after_send(~A: Data, sent: Outcome(Unit), input: IO(Outcome(A))) -> IO(Outcome(A)):
  match sent:
    case Fail{st}: IO.pure(Outcome(A), Fail{st})
    case Done{_}: input

def response_stream(~A: Data, ~B: Data, request: A, out: Write<A>, answer: IO(Outcome(B))) -> IO(Outcome(B)):
  do IO<Outcome(B)>:
    sent : Outcome(Unit) <- send_all(~A, [request], out)
    after_send(~B, sent, answer)

def write_list(~A: Data, result: Outcome(List<&2, A>), out: Write<A>) -> IO(Unit):
  match result out:
    case _ FailedWrite{_}: IO.pure(Unit, Unit{})
    case Fail{st} Write{_, finish}: finish(st)
    case Done{xs} sink:
      do IO<Unit>:
        sent : Outcome(Unit) <- send_all(~A, xs, sink)
        return Unit{}

def list_handler(~A: Data, result: IO(Outcome(List<&2, A>)), out: Write<A>) -> IO(Unit):
  IO.bind(Outcome(List<&2, A>), Unit, result, r => write_list(~A, r, out))

# Drain responses while sending a batch. A peer can reply to every request
# as it arrives, even when a batch exceeds the HTTP/2 event channel capacity.
def batch(~A: Data, ~B: Data, values: List<&2, A>, out: Write<A>, answer: IO(Outcome(B))) -> IO(Outcome(B)):
  do IO<Outcome(B)>:
    result : Chan(Outcome(B)) <- IO.fork(Outcome(B), answer)
    sent : Outcome(Unit) <- send_all(~A, values, out)
    after_send(~B, sent, IO.join(Outcome(B), result))

def client_many(~A: Data, ~B: Data, values: List<&2, A>, out: Write<A>, incoming: IO(Read<B>)) -> IO(Outcome(List<&2, B>)):
  batch(~A, ~List<&2, B>, values, out, all(~B, incoming))

def client_one(~A: Data, ~B: Data, values: List<&2, A>, out: Write<A>, incoming: IO(Read<B>)) -> IO(Outcome(B)):
  batch(~A, ~B, values, out, IO.bind(Read<B>, Outcome(B), incoming,
    e => single(~B, e, G.GStatus{13, "expected one response message"})))

# Publishing the stream id gives the timeout branch a stream to reset. If
# the deadline wins during open, closing the slot makes a late opener cancel.
def registered(~A: Data, active: Result<&1, &1, U32, Unit>, action: IO(Outcome(A))) -> IO(Outcome(A)):
  match active:
    case Done{_}: action
    case Fail{_}: IO.pure(Outcome(A), Fail{G.GStatus{4, "deadline exceeded"}})

def opened(~A: Data, interact: U32 -> IO(Outcome(A)), +conn: Chan(H2.H2Msg), +events: Chan(H2.SEv),
  slot: Chan(U32), event: Maybe<&1, H2.SEv>) -> IO(Outcome(A)):
  match event:
    case Some{H2.SOpened{+sid}}:
      do IO<Outcome(A)>:
        active : Result<&1, &1, U32, Unit> <- Chan.send(U32, slot, sid)
        result : Outcome(A) <- registered(~A, active, interact(sid))
        Chan.close(H2.SEv, events)
        # Reset is a no-op when both halves have already closed. It releases
        # an open half when an application returns early or abandons a call.
        close_request(sid, conn, G.GStatus{1, "exchange finished"})
        return result
    case Some{H2.SGone{why}}: IO.pure(Outcome(A), Fail{G.GStatus{14, why}})
    case _: IO.pure(Outcome(A), Fail{G.GStatus{14, "connection closed"}})

def opening(~A: Data, interact: U32 -> IO(Outcome(A)), +conn: Chan(H2.H2Msg), +events: Chan(H2.SEv), slot: Chan(U32),
  result: Result<&1, &1, H2.H2Msg, Unit>) -> IO(Outcome(A)):
  match result:
    case Fail{_}: IO.pure(Outcome(A), Fail{G.GStatus{14, "connection closed"}})
    case Done{_}:
      do IO<Outcome(A)>:
        e : Maybe<&1, H2.SEv> <- Chan.recv(H2.SEv, events)
        opened(~A, interact, conn, events, slot, e)

def cancel_active(id: Maybe<&1, U32>, conn: Chan(H2.H2Msg), events: Chan(H2.SEv)) -> IO(Unit):
  match id:
    case None{}: IO.pure(Unit, Unit{})
    case Some{sid}:
      do IO<Unit>:
        Chan.close(H2.SEv, events)
        close_request(sid, conn, G.GStatus{4, "deadline exceeded"})

def client_timeout(~A: Data, result: Maybe<&1, Outcome(A)>, +slot: Chan(U32), conn: Chan(H2.H2Msg), events: Chan(H2.SEv)) -> IO(Outcome(A)):
  match result:
    case Some{r}: IO.pure(Outcome(A), r)
    case None{}:
      do IO<Outcome(A)>:
        Chan.close(U32, slot)
        id : Maybe<&1, U32> <- Chan.recv(U32, slot)
        cancel_active(id, conn, events)
        return Fail{G.GStatus{4, "deadline exceeded"}}

def timed(~A: Data, ms: U32, action: IO(Outcome(A)), slot: Chan(U32), conn: Chan(H2.H2Msg), events: Chan(H2.SEv)) -> IO(Outcome(A)):
  match ms:
    case 0: action
    case delay:
      do IO<Outcome(A)>:
        r : Maybe<&1, Outcome(A)> <- IO.within(Outcome(A), delay, action)
        client_timeout(~A, r, slot, conn, events)

def exchange(~A: Data, ~B: Data, ~C: Data, ~encode: A -> Maybe<&2, List<&2, U32>>, ~decode: List<&2, U32> -> Maybe<&2, B>,
  +conn: Chan(H2.H2Msg), path: String, interact: Write<A> -> IO(Read<B>) -> IO(Outcome(C)), +ms: U32) -> IO(Outcome(C)):
  do IO<Outcome(C)>:
    +events : Chan(H2.SEv) <- Chan.new(H2.SEv, 256)
    +slot : Chan(U32) <- Chan.new(U32, 1)
    start : (U32 -> IO(Outcome(C))) = sid => interact(writer(~A, ~encode, Request{sid, conn}),
      read(~B, ~decode, ready(Source{events, True{}}), G.GStatus{13, "invalid protobuf response"}))
    action : IO(Outcome(C)) = IO.bind(Result<&1, &1, H2.H2Msg, Unit>, Outcome(C),
      Chan.send(H2.H2Msg, conn, H2.MOpen{G.Grpc.call_headers(path, ms), False{}, events}),
      ok => opening(~C, start, conn, events, slot, ok))
    timed(~C, ms, action, slot, conn, events)

type Call is Data:
  Call{path: String, context: Context, input: Cursor, sink: Rpc.GSink}

def server_timeout(ms: U32, action: IO(Unit), sid: U32, conn: Chan(H2.H2Msg)) -> IO(Unit):
  match ms:
    case 0: action
    case delay:
      do IO<Unit>:
        r : Maybe<&1, Unit> <- IO.within(Unit, delay, action)
        Rpc.Grpc.expired(r, sid, conn)

def start_call(dispatch: Call -> IO(Unit), +hs: List<&2, Http.Header>, ended: Bool, +events: Chan(H2.SEv),
  +sid: U32, +conn: Chan(H2.H2Msg), valid: Bool) -> IO(Unit):
  match valid:
    case False{}: Rpc.Grpc.put(conn, sid, Wire.CHead{[Http.Header{":status", "415"}], True{}})
    case True{}:
      +ms = Rpc.Grpc.deadline(G.Grpc.hdr(hs, "grpc-timeout"))
      path = Maybe.default(&2, String, G.Grpc.hdr(hs, ":path"), "")
      input : Cursor = ready(after_data(events, False{}, ended))
      server_timeout(ms, dispatch(Call{path, Context{hs, ms}, input, Rpc.GSink{sid, conn, False{}}}), sid, conn)

def accepted(dispatch: Call -> IO(Unit), e: Maybe<&1, H2.SEv>, +events: Chan(H2.SEv), sid: U32, conn: Chan(H2.H2Msg)) -> IO(Unit):
  match e:
    case Some{H2.SGot{Wire.EvHeaders{_, +hs, ended}}}: start_call(dispatch, hs, ended, events, sid, conn, G.Grpc.is_call(hs))
    case _: IO.pure(Unit, Unit{})

def attend(dispatch: Call -> IO(Unit), req: H2.H2Req) -> IO(Unit):
  match req:
    case H2.H2Req{sid, +events, conn}:
      do IO<Unit>:
        e : Maybe<&1, H2.SEv> <- Chan.recv(H2.SEv, events)
        accepted(dispatch, e, events, sid, conn)
        Chan.close(H2.SEv, events)

def intake(~dispatch: Call -> IO(Unit), fuel: Nat, req: Maybe<&1, H2.H2Req>, +requests: Chan(H2.H2Req)) -> IO(Unit):
  match fuel req:
    case 0n _: IO.pure(Unit, Unit{})
    case _ None{}: IO.pure(Unit, Unit{})
    case 1n+f Some{r}:
      do IO<Unit>:
        IO.spawn(Unit, attend(dispatch, r))
        next : Maybe<&1, H2.H2Req> <- Chan.recv(H2.H2Req, requests)
        intake(~dispatch, f, next, requests)

def serve(~dispatch: Call -> IO(Unit), listener: Listener) -> IO(Unit):
  do IO<Unit>:
    +requests : Chan(H2.H2Req) <- Chan.new(H2.H2Req, 256)
    IO.spawn(Unit, IO.bind(Maybe<&1, H2.H2Req>, Unit, Chan.recv(H2.H2Req, requests),
      r => intake(~dispatch, H2.H2io.fuel(), r, requests)))
    H2.H2io.serve(listener, requests)

def unary_result(~A: Data, ~encode: A -> Maybe<&2, List<&2, U32>>, answer: Outcome(A), k: Rpc.GSink) -> IO(Unit):
  Rpc.Grpc.reply(k, Result.bind(&2, &2, G.GStatus, A, List<&2, U32>, answer, x => encoded(encode(x))))

def apply_single(~A: Data, result: Outcome(A), handle: A -> IO(Unit), k: Rpc.GSink) -> IO(Unit):
  match result:
    case Fail{st}: Rpc.Grpc.finish(k, st)
    case Done{x}: handle(x)

def one_request(~A: Data, incoming: IO(Read<A>), handle: A -> IO(Unit), k: Rpc.GSink) -> IO(Unit):
  do IO<Unit>:
    e : Read<A> <- incoming
    r : Outcome(A) <- single(~A, e, G.GStatus{3, "expected one request message"})
    apply_single(~A, r, handle, k)
