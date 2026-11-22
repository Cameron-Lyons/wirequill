# Wirequill

The plugin, build driver, and test suite are written in Bend. The native executable reads a binary `CodeGeneratorRequest` on stdin and returns typed proto3 messages, wire codecs, gRPC clients, and server dispatchers in a `CodeGeneratorResponse` on stdout.

## Build and generate

From `~/wirequill`, run `bend build.bend`. The build driver embeds the support modules, compiles `build/wirequill`, and creates `build/protoc-gen-wirequill` for plugin discovery. The tested toolchain is Bend 2.0.40 with its native compiler and protoc 36.2 on Linux. The plugin reads and writes the plugin protocol through `/dev/stdin` and `/dev/stdout`. Bend fetches its pinned libraries on the first build.

For an input file named `service.proto` in the current directory and an existing output directory named `generated`, run `protoc -I . --plugin=./build/protoc-gen-wirequill --wirequill_out=generated service.proto`. A requested schema containing a service also produces gRPC bindings.

With `~/wirequill/build` on `PATH`, protoc finds Wirequill automatically and the `--plugin` argument is optional. The build also supplies `protoc-gen-proto` and `protoc-gen-grpc`, so existing `--proto_out` and `--grpc_out` commands work. To try the examples, run `bend tests/fixtures.bend inputs` with an empty `inputs` directory, then use `-I inputs` and either `fixture.proto` or `echo.proto` in the command above.

Generate related root files in **one invocation** and choose a dedicated output directory. Each invocation writes a single `schema.bend` containing the messages and enums in the proto3 import closure, plus service stubs for the requested root files. Keep the generated sibling `runtime.bend`, `message_values.bend`, and, for services, `grpc_runtime.bend` beside it. Separate invocations into the same directory replace the previous schema.

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

Singular embedded messages merge repeated wire occurrences. Typed decoders discard unknown fields, so proxying a newer schema through an older generated type can lose data. Recursive message graphs compile to native Bend using `@unsafe` adapters for forward calls. Bend’s termination checker cannot certify those adapters. The generator accepts proto3 files throughout the import closure. Proto2 and Editions produce a diagnostic. Plugin requests are limited to 64 MiB and descriptor nesting to 128 messages.

## gRPC

For `rpc Say(Value) returns (Value)` on `demo.Echo`, the client call is `S.PB_demo_Echo.call.Say(conn, S.PB_demo_Value{42}, 3000)`. Here `conn` is the upstream HTTP/2 connection channel and the timeout is in milliseconds. The result is `IO(Result<&2, &2, G.GStatus, S.PB_demo_Value>)`. The canonical path is available as `S.PB_demo_Echo.path.Say()`.

On the server, construct `S.PB_demo_Echo.Handlers{say, list_values}` with typed handlers in method declaration order and pass it and the inbound call to `S.PB_demo_Echo.dispatch`. Each handler receives the call metadata and timeout through `GR.Context`, followed by its typed request. Returning `Fail{G.GStatus{code, message}}` propagates that status to the client.

Unary and server-streaming calls use the upstream HTTP/2 transport. A server-streaming handler returns a list of typed responses, and the client receives the ordered list when the stream completes. Client-streaming and bidirectional RPCs produce a generation error because this transport accepts a single request message per call. The runnable example starts a server, opens a connection, calls both supported method shapes, and checks status propagation. [Example schemas](tests/fixtures.bend) · [Handlers and client calls](tests/grpc/roundtrip.bend)

## Verification

Run `bend test.bend` from the project root to reproduce the CI checks. The runner builds Wirequill, checks the generator and its imports with `--check-only`, and writes the schema fixtures into a temporary directory. It exercises all three plugin names through normal `protoc` discovery and compares two independent generations of the same service byte for byte.

GitHub Actions runs **Verify Wirequill** on pull requests, merge queues, and pushes to `main` or `master`. The job uses Ubuntu 26.04, installs Clang from the LLVM 23 package channel, and verifies the SHA-256 digests of Bend 2.0.40 and protoc 36.2. The suite has been verified with Clang 23.1.6. [CI workflow](.github/workflows/ci.yml)

The tests invoke the plugin through `protoc`, compile its output with Bend, change a typed message between `protoc --encode` and `protoc --decode`, and run a client and server over an HTTP/2 Unix socket. They also exercise malformed wire data, invalid schemas, and unsupported methods. For local runs, `CC` selects Clang and `PROTOC` selects the protobuf compiler.

The Bend CLI runs the byte-stream helper with `bend-kit-process@0.5.2.1`. This avoids a native compilation issue in that dependency on glibc 2.44. The plugin and generated bindings are tested as native executables.

The generated codecs use `bend-kit-protobuf@0.2.2.0` and `bend-kit-bytes@0.3.3.1`. Service bindings use the gRPC transport from `bend-kube-runtime@0.10.0.0`, pinned at `0xc8d18670ba37041507e7f53cc7972ec6`. The codec repository also ships a Python message generator. This project implements its own descriptor reader and generator in Bend. [Wire codec](https://github.com/paymog/bend-kit/tree/main/protobuf) · [gRPC transport](https://hub.bend-lang.com/0xc8d18670ba37041507e7f53cc7972ec6/src/grpcio.bend) · [Official plugin protocol](https://github.com/protocolbuffers/protobuf/blob/main/src/google/protobuf/compiler/plugin.proto)

## License

Wirequill is available under the [MIT License](LICENSE).
