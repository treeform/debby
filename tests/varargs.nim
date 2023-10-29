import std/strutils, jsony

type Argument = object
  kind*: string
  value*: string

proc toArgument[T](v: T): Argument =
  result.kind = $T
  result.value = v.toJson()

proc takesVarargs(args: varargs[Argument, toArgument]) =
  for arg in args:
    echo arg.kind, ":", arg.value

takesVarArgs("hi", "how are you?", 1)
