## Shared allowlist for ANSI tokens already parsed by TerminalStyle.

proc isSafeSgr*(sequence: string): bool =
  ## SGR has no private prefix or intermediate bytes. Numeric parameters,
  ## semicolon separators, and colon subparameters cover ordinary, indexed,
  ## and RGB styling, including an empty reset parameter list.
  if sequence.len < 3 or sequence[0] != '\e' or sequence[1] != '[' or
      sequence[^1] != 'm':
    return false
  for index in 2 ..< sequence.len - 1:
    if sequence[index] notin {'0' .. '9', ';', ':'}:
      return false
  true
