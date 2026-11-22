import Base
import 0xc8d18670ba37041507e7f53cc7972ec6/src/grpc.bend as G
import 0xc8d18670ba37041507e7f53cc7972ec6/src/grpcio.bend as Rpc
import 0xc8d18670ba37041507e7f53cc7972ec6/src/h2io.bend as H2
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
