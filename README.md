# Wirequill

Wirequill generates Bend types and binary codecs for proto3, plus gRPC clients and server dispatchers for all four RPC shapes. The protoc plugin, generated code, runtime adapters, build driver, and test suite are written in Bend.

## Build and generate

From the repository root, run `bend build.bend`. The build driver embeds the support modules, compiles `build/wirequill`, and creates `build/protoc-gen-wirequill` for plugin discovery. The tested toolchain is Bend 2.0.40 with its native compiler and protoc 36.2 on Linux. The plugin reads and writes the plugin protocol through `/dev/stdin` and `/dev/stdout`. Bend fetches its pinned libraries on the first build.

For an input file named `service.proto` in the current directory and an existing output directory named `generated`, run `protoc -I . --plugin=./build/protoc-gen-wirequill --wirequill_out=generated service.proto`. A requested schema containing a service also produces gRPC bindings.

With `~/wirequill/build` on `PATH`, protoc finds Wirequill automatically and the `--plugin` argument is optional. The build also supplies `protoc-gen-proto` and `protoc-gen-grpc`, so existing `--proto_out` and `--grpc_out` commands work. To try the examples, run `bend tests/fixtures.bend inputs` with an empty `inputs` directory, then use `-I inputs` and either `fixture.proto` or `echo.proto` in the command above.

Generate related root files in one invocation so they share the same Bend types. By default, Wirequill writes `schema.bend` with messages and enums from the proto3 import closure and service stubs for the requested roots. Keep the generated `runtime.bend`, `message_values.bend`, and, for services, `grpc_runtime.bend` beside the schema.

| Generator option | Effect |
| --- | --- |
| `module=NAME` | Writes `NAME.bend`. Choose a distinct module name for each independent invocation that shares an output directory. The name must be a single identifier and the support module names are reserved. |
| `preserve_unknown` | Adds a final `unknown_fields: List<&2, R.Field>` member to every generated message, including nested messages and map entries. Decoding and re-encoding retains unrecognized fields, including groups and known field numbers with a different wire type. |

For example, `--wirequill_opt=module=orders,preserve_unknown --wirequill_out=generated` writes `generated/orders.bend`. Regenerating with the same module name replaces that schema. Separate schema modules each define their own types for shared imports.

## Messages

The example declares `demo.Value` with one `uint32` field. A sibling Bend module can use its generated type directly.

```bend
import Base
import ./schema.bend as S

def example() -> Maybe<&2, S.PB_demo_Value>:
  do Maybe<&2, S.PB_demo_Value>:
    bytes : List<&2, U32> <- S.PB_demo_Value.encode(S.PB_demo_Value{42})
    S.PB_demo_Value.decode(bytes)
```

Every message has `.default()`, `.encode(value)`, and `.decode(bytes)`. Both conversions return `Maybe`. Invalid wire data, out-of-range byte values, and invalid text can return `None{}`. The equivalent `.encode_checked(value)` is used by the stubs.

| Proto3 | Generated Bend representation |
| --- | --- |
| 32-bit integers | `U32`, with signed values held as two’s-complement bits |
| 64-bit integers | `R.Word64{hi, lo}`, with signed values held as two’s-complement bits |
| `float`, `double` | `F32`, or `R.Word64{hi, lo}` holding the IEEE 754 double bits |
| `bool`, `string`, `bytes` | `Bool`, `String`, `List<&2, U32>` |
| Enum | Typed numeric wrapper with a `.value_NAME()` function per declared constant. Unknown numeric values survive decoding. |
| Embedded message or explicit `optional` | `Maybe<&2, T>` retains presence, including present zero and empty values. |
| `repeated` | `List<&2, T>` in wire order. Numeric fields accept packed and unpacked occurrences. |
| `map<K,V>` | Bend `Map` of typed entry records. The entry’s `.key(entry)` gives the lookup string. Duplicate keys keep the last entry. |
| `oneof` | One optional discriminated union per group. Its constructor identifies the selected field, including a selected default value. |

Qualified type names start with `PB_`. Package and nesting separators become underscores, and literal underscores become `_0`. Field labels use `f_` and oneof slots use `o_`. Constructor arguments follow descriptor field order, with the oneof slots at the end. Import the generated `runtime.bend` as `R` to construct a 64-bit value.

Singular embedded messages merge repeated wire occurrences. By default, typed decoders discard unknown fields. Use `preserve_unknown` when an older application must pass newer fields through. It preserves their values and relative order. Known fields are emitted first, and the encoder may normalize their binary representation.

Recursive message graphs use `@unsafe` adapters for forward calls that Bend’s termination checker cannot certify. Generated types and RPC signatures use proto3 declarations. A proto3 root may import proto2 or Editions files for custom options. Requesting those files as roots or using their types in a generated field or RPC produces a diagnostic. The plugin accepts requests up to 64 MiB and descriptor nesting up to 128 messages.

## gRPC

For `rpc Say(Value) returns (Value)` on `demo.Echo`, the client call is `S.PB_demo_Echo.call.Say(conn, S.PB_demo_Value{42}, 3000)`. Here `conn` is the upstream HTTP/2 connection channel and the timeout is in milliseconds. The result is `IO(Result<&2, &2, G.GStatus, S.PB_demo_Value>)`. The canonical path is available as `S.PB_demo_Echo.path.Say()`.

| RPC shape | Client `.call` input and result payload | Server handler after `GR.Context` |
| --- | --- | --- |
| Unary | One request → one response | Takes one request and returns one response |
| Server streaming | One request → ordered list of responses | Takes one request and returns a list or writes responses incrementally |
| Client streaming | List of requests → one response | Reads requests incrementally and returns one response |
| Bidirectional | List of requests → ordered list of responses | Reads requests and writes responses incrementally |

For incremental server streaming, call `.stream.Method(~ResultType, conn, request, consume, timeout_ms)`. The consumer receives an `IO(GR.Read<Response>)` and can process the first message while the server is still working. Implement the server method with `.StreamingHandlers` and `.accept_streaming` to send replies through a `GR.Write<Response>`.

For an interactive upload or bidirectional call, use `.exchange.Method(~ResultType, conn, interact, timeout_ms)`. The callback receives a `GR.Write<Request>` and an `IO(GR.Read<Response>)`. Sending one message returns the writer for the next send. Finishing with `G.GStatus{0, ""}` closes the request side. A read yields `Item{value, next}`, `End{}`, or `Refused{status}`. The client can receive a reply before sending its next request.

On the server, pass a call handler to `GR.serve(~handle, listener)`. For the example service, the handler calls `S.PB_demo_Echo.accept(S.PB_demo_Echo.Handlers{say, list_values, collect_values, chat}, call)`. Handlers receive metadata and the timeout through `GR.Context`. Unary and client-streaming handlers return a `GR.Outcome`. A bidirectional handler finishes its writer with the final gRPC status. The existing `.dispatch(handlers, call)` entry point accepts the upstream single-request `Rpc.GCall`.

The transport uses cleartext HTTP/2 and supports uncompressed messages up to 4 MiB. The example exercises list-based calls, early server replies, an interleaved exchange, deadlines, and error statuses over a Unix socket. [Example schemas](tests/fixtures.bend) · [Handlers and client calls](tests/grpc/roundtrip.bend)

## Verification

Run `bend test.bend` from the project root to reproduce the CI checks. The runner builds Wirequill, checks the generator and its imports with `--check-only`, and writes the schema fixtures into a temporary directory. It exercises all three plugin names through normal `protoc` discovery and compares two independent generations of the same service byte for byte.

GitHub Actions runs **Verify Wirequill** on pull requests, merge queues, and pushes to `main` or `master`. The job uses Ubuntu 26.04, installs Clang from the LLVM 23 package channel, and verifies the SHA-256 digests of Bend 2.0.40 and protoc 36.2. The suite has been verified with Clang 23.1.6. [CI workflow](.github/workflows/ci.yml)

The tests invoke the plugin through `protoc`, compile its output with Bend, change a typed message between `protoc --encode` and `protoc --decode`, and run a client and server over an HTTP/2 Unix socket. They also exercise all four RPC shapes, malformed frames, descriptor diagnostics, custom-option imports, and unknown fields carried through a typed edit. For local runs, `CC` selects Clang and `PROTOC` selects the protobuf compiler.

The Bend CLI runs the byte-stream helper with `bend-kit-process@0.5.2.1`. This avoids a native compilation issue in that dependency on glibc 2.44. The plugin and generated bindings are tested as native executables.

The generated codecs use `bend-kit-protobuf@0.2.2.0` and `bend-kit-bytes@0.3.3.1`. Service bindings use the gRPC transport from `bend-kube-runtime@0.10.0.0`, pinned at `0xc8d18670ba37041507e7f53cc7972ec6`. The codec repository also ships a Python message generator. This project implements its own descriptor reader and generator in Bend. [Wire codec](https://github.com/paymog/bend-kit/tree/main/protobuf) · [gRPC transport](https://hub.bend-lang.com/0xc8d18670ba37041507e7f53cc7972ec6/src/grpcio.bend) · [Official plugin protocol](https://github.com/protocolbuffers/protobuf/blob/main/src/google/protobuf/compiler/plugin.proto)

## License

Wirequill is available under the [MIT License](LICENSE).
