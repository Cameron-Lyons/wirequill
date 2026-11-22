# File and subprocess operations shared by the build and test entry points.
import Base

def tool(env: String, fallback: String) -> IO(String):
  do IO<String>:
    r : Result<&1, &1, U32 & String, String> <- IO.get_env(env)
    return Result.default(&1, &1, U32 & String, String, r, fallback)

def run(program: String, args: List<String>, input: String, timeout_ms: U32) -> IO(U32 & (String & String)):
  IO.try(U32 & (String & String), Process.run(program, args, input, 4194304, timeout_ms))

def checked(program: String, result: U32 & (String & String)) -> IO(Unit):
  match result:
    case (0, (output, errors)): IO.pure(Unit, Unit{})
    case (code, (output, errors)):
      IO.die(Unit, code, program ++ " failed\n" ++ output ++ errors)

def command(+program: String, args: List<String>) -> IO(Unit):
  do IO<Unit>:
    result : U32 & (String & String) <- run(program, args, "", 300000)
    checked(program, result)

def finish_read(got: File & Result<&1, &1, U32 & String, String>) -> IO(String):
  (f, raw) = got
  do IO<String>:
    File.close(f)
    IO.pass(String, raw)

def read_sized(pair: File & Result<&1, &1, U32 & String, U32>) -> IO(String):
  (f, size) = pair
  do IO<String>:
    n : U32 <- IO.pass(U32, size)
    got : File & Result<&1, &1, U32 & String, String> <- File.read(f, n)
    finish_read(got)

def read_text(path: String) -> IO(String):
  do IO<String>:
    f : File <- IO.try(File, File.open(path, "r"))
    size : File & Result<&1, &1, U32 & String, U32> <- File.size(f)
    read_sized(size)

def finish_write(pair: File & Result<&1, &1, U32 & String, Unit>) -> IO(Unit):
  (f, result) = pair
  do IO<Unit>:
    File.close(f)
    IO.pass(Unit, result)

def write_text(path: String, text: String) -> IO(Unit):
  do IO<Unit>:
    f : File <- IO.try(File, File.open(path, "w"))
    wrote : File & Result<&1, &1, U32 & String, Unit> <- File.write(f, text)
    finish_write(wrote)
