# Build with `bend build.bend` from the project root.
import Base
import ./tools/embed.bend as Embed
import ./tools/host.bend as Host

def main() -> IO(Unit):
  do IO<Unit>:
    compiler : String <- Host.tool("BEND", "bend")
    Host.command("mkdir", ["-p", "build"])
    # Stage each build separately. Existing plugin binaries stay usable while
    # a new compiler process is running, including when that process fails.
    nonce : U32 <- IO.try(U32, IO.random_u32())
    +suffix : String = "." ++ U32.show(nonce)
    +assets : String = "build/assets" ++ suffix ++ ".bend"
    source : String <- Embed.source()
    Host.write_text(assets, source)
    Host.command("mv", [assets, "build/assets.bend"])
    +binary : String = "build/wirequill" ++ suffix
    Host.command(compiler, ["main.bend", "-o", binary])
    Host.command("mv", [binary, "build/wirequill"])
    Host.command("ln", ["-sf", "wirequill", "build/protoc-gen-wirequill"])
    Host.command("ln", ["-sf", "wirequill", "build/protoc-gen-proto"])
    Host.command("ln", ["-sf", "wirequill", "build/protoc-gen-grpc"])
