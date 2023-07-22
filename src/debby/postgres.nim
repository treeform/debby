import common, jsony, std/tables, std/strformat, std/strutils, std/sets
export common, jsony

when defined(windows):
  const Lib = "libpq.dll"
elif defined(macosx):
  const Lib = "libpq.dylib"
else:
  const Lib = "libpq.so(.5|)"

type
  Statement* = pointer
  Result* = pointer

  ConnStatusType* = enum
    CONNECTION_OK = 0, CONNECTION_BAD, CONNECTION_STARTED, CONNECTION_MADE,
    CONNECTION_AWAITING_RESPONSE, CONNECTION_AUTH_OK, CONNECTION_SETENV,
    CONNECTION_SSL_STARTUP, CONNECTION_NEEDED, CONNECTION_CHECK_WRITABLE,
    CONNECTION_CONSUME, CONNECTION_GSS_STARTUP, CONNECTION_CHECK_TARGET

  ExecStatusType* = enum
    PGRES_EMPTY_QUERY = 0, PGRES_COMMAND_OK, PGRES_TUPLES_OK, PGRES_COPY_OUT,
    PGRES_COPY_IN, PGRES_BAD_RESPONSE, PGRES_NONFATAL_ERROR, PGRES_FATAL_ERROR,
    PGRES_COPY_BOTH, PGRES_SINGLE_TUPLE

{.push importc, cdecl, dynlib: Lib.}

proc PQsetdbLogin*(
  pghost: cstring,
  pgport: cstring,
  pgoptions: cstring,
  pgtty: cstring,
  dbName: cstring,
  login: cstring,
  pwd: cstring
): DB

proc PQstatus*(
  conn: DB
): ConnStatusType

proc PQerrorMessage*(
  conn: DB
): cstring

proc PQfinish*(
  conn: DB
)

proc PQexec*(
  conn: DB,
  query: cstring
): Result

proc PQexecParams*(
  conn: DB,
  command: cstring,
  nParams: int32,
  paramTypes: ptr int32,
  paramValues: cstringArray,
  paramLengths: ptr int32,
  paramFormats: ptr int32,
  resultFormat: int32
): Result

proc PQresultStatus*(
  res: Result
): ExecStatusType

proc PQntuples*(
  res: Result
): int32

proc PQnfields*(
  res: Result
): int32

proc PQclear*(
  res: Result
)

proc PQgetvalue*(
  res: Result,
  tup_num: int32,
  field_num: int32
): cstring

proc PQfname*(
  res: Result,
  field_num: int32
): cstring

{.pop.}

proc dbError*(db: DB) {.noreturn.} =
  ## raises a DbError exception.
  var e: ref DbError
  new(e)
  e.msg = "Postgres: " & $PQerrorMessage(db)
  raise e

proc openDatabase*(host, port, user, password, database: string): Db =

  result = PQsetdbLogin(
    host.cstring,
    port.cstring,
    nil,
    nil,
    database.cstring,
    user.cstring,
    password.cstring
  )
  if PQstatus(result) != CONNECTION_OK:
    dbError(result)

proc prepareQuery(
  db: DB,
  query: string,
  args: varargs[string]
): Result =
  when defined(debbyShowSql):
    debugEcho(query)

  if query.count('?') != args.len:
    dbError("Number of arguments and number of ? in query does not match")

  if args.len > 0:
    var pgQuery = ""
    var argNum = 1
    for c in query:
      if c == '?':
        # Use the $number escape:
        pgQuery.add "$"
        pgQuery.add $argNum
        inc argNum
      else:
        pgQuery.add c

    var
      paramData: seq[string]
      paramLengths: seq[int32]
      paramFormats: seq[int32]

    for arg in args:
      paramData.add(arg)
      paramLengths.add(arg.len.int32)
      paramFormats.add(0)

    var paramValues = allocCStringArray(paramData)

    result = PQexecParams(
      db,
      pgQuery.cstring,
      args.len.int32,
      nil,    # let the backend deduce param type
      paramValues,
      paramLengths[0].addr,
      paramFormats[0].addr,
      0 # ask for binary results
    )

    deallocCStringArray(paramValues)

  else:
    result = PQexec(db, query)

  if PQresultStatus(result) in {
    PGRES_BAD_RESPONSE,
    PGRES_NONFATAL_ERROR,
    PGRES_FATAL_ERROR
  }:
    echo "ERROR!!!"
    dbError(db)

proc readRow(res: Result, r: var Row, line, cols: int32) =
  for col in 0'i32..cols-1:
    setLen(r[col], 0)
    let x = PQgetvalue(res, line, col)
    if x.isNil:
      r[col] = ""
    else:
      add(r[col], x)

proc getAllRows(res: Result): seq[Row] =
  let N = PQntuples(res)
  let L = PQnfields(res)
  result = newSeqOfCap[Row](N)
  var row = newSeq[string](L)
  for i in 0'i32..N-1:
    readRow(res, row, i, L)
    result.add(row)
  PQclear(res)

proc query*(
  db: DB,
  query: string,
  args: varargs[string, `$`]
): seq[Row] {.discardable.} =
  let res = prepareQuery(db, query, args)
  result = getAllRows(res)

proc close*(db: Db) =
  PQfinish(db)

proc tableExists*[T](db: Db, t: typedesc[T]): bool =
  ## Checks if table exists.
  for row in db.query(&"""SELECT
    column_name,
    data_type
FROM
    information_schema.columns
WHERE
    table_schema = 'public'
    AND table_name = '{T.tableName}';
"""):
    result = true
    break

proc tableNameQuoted*[T](t: typedesc[T]): string =
  ## Converts object type name to table name.
  '"' & T.tableName & '"'

proc dropTable*[T](db: Db, t: typedesc[T]) =
  ## Removes tables, errors out if it does not exist.
  db.query("DROP TABLE " & T.tableNameQuoted)

proc dropTableIfExists*[T](db: Db, t: typedesc[T]) =
  ## Removes tables if it exists.
  db.query("DROP TABLE IF EXISTS " & T.tableNameQuoted)

proc sqlType(name, t: string): string =
  ## Converts nim type to SQL type.
  case t:
  of "string": "text"
  of "Bytes": "bytea"
  of "int8", "int16": "smallint"
  of "uint8", "uint16", "int32": "integer"
  of "uint32", "int64", "int": "integer"
  of "uint", "uint64": "numeric(20)"
  of "float", "float32": "real"
  of "float64": "double precision"
  of "bool": "boolean"
  else: "jsonb"

proc createTableStatement*[T: ref object](db: Db, t: typedesc[T]): string =
  ## Given an object creates its table create statement.
  validateObj(t)
  let tmp = T()
  result.add "CREATE TABLE "
  result.add T.tableNameQuoted
  result.add " (\n"
  for name, field in tmp[].fieldPairs:
    result.add "  "
    result.add name.toSnakeCase
    result.add " "
    if name == "id":
      result.add " SERIAL PRIMARY KEY"
    else:
      result.add sqlType(name, $type(field))
    result.add ",\n"
  result.removeSuffix(",\n")
  result.add "\n)"

proc createTable*[T: ref object](db: Db, t: typedesc[T]) =
  ## Creates a table, errors out if it already exists.
  db.query(db.createTableStatement(t))

proc checkTable*[T: ref object](db: Db, t: typedesc[T]) =
  ## Checks to see if table matches the object.
  ## And recommends to create whole table or alter it.
  let tmp = T()
  var issues: seq[string]

  if not db.tableExists(T):
    when defined(debbyYOLO):
      db.createTable(T)
    else:
      issues.add "Table " & T.tableNameQuoted & " does not exist."
      issues.add "Create it with:"
      issues.add db.createTableStatement(t)
  else:
    var tableSchema: Table[string, string]
    for row in db.query(&"""SELECT
    column_name,
    data_type
FROM
    information_schema.columns
WHERE
    table_schema = 'public'
    AND table_name   = '{T.tableName}';
"""):
      let
        fieldName = row[0]
        fieldType = row[1]
      tableSchema[fieldName] = fieldType

    for fieldName, field in tmp[].fieldPairs:
      let sqlType = sqlType(fieldName, $type(field))
      if fieldName.toSnakeCase in tableSchema:
        if tableSchema[fieldName.toSnakeCase] == sqlType:
          discard # good everything matches
        else:
          issues.add "Field " & T.tableName & "." & fieldName & " expected type " & sqlType & " but got " & tableSchema[fieldName]
          # TODO create new table with right data
          # copy old data into new table
          # delete old table
          # rename new table
      else:
        let addFieldStatement = "ALTER TABLE " & T.tableNameQuoted & " ADD COLUMN " & fieldName.toSnakeCase & " "  & sqlType
        if defined(debbyYOLO):
          db.query(addFieldStatement)
        else:
          issues.add "Field " & T.tableNameQuoted & "." & fieldName & " is missing"
          issues.add "Add it with:"
          issues.add addFieldStatement

  if issues.len != 0:
    issues.add "Or compile --d:debbyYOLO to do this automatically"
    raise newException(DBError, issues.join("\n"))

proc insert*[T: ref object](db: Db, obj: T) =
  ## Inserts the object into the database.
  for row in db.insertInner(obj, " RETURNING id"):
    obj.id = row[0].parseInt()

proc query*[T](
  db: Db,
  t: typedesc[T],
  query: string,
  args: varargs[string, `$`]
): seq[T] =

  let tmp = T()

  var
    statement = prepareQuery(db, query, args)
    columnCount = PQnfields(statement)
    rowCount = PQntuples(statement)
    headerIndex: seq[int]

  for i in 0 ..< columnCount:
    let columnName = PQfname(statement, i)
    var
      j = 0
      found = false
    for fieldName, field in tmp[].fieldPairs:
      if columnName == fieldName.toSnakeCase:
        found = true
        headerIndex.add(j)
        break
      inc j
    if not found:
      raise newException(
        DBError,
        "Can't map query to object, missing " & $columnName
      )

  try:
    for j in 0 ..< rowCount:
      var row = newSeq[string](columnCount)
      readRow(statement, row, j, columnCount)
      let tmp = T()
      var i = 0
      for fieldName, field in tmp[].fieldPairs:
        sqlParse(row[headerIndex[i]], field)
        inc i
      result.add(tmp)
  finally:
    PQclear(statement)

proc createIndexStatement*[T: ref object](
  db: Db,
  t: typedesc[T],
  ifNotExists: bool,
  params: varargs[string]
): string =
  result.add "CREATE INDEX "
  if ifNotExists:
    result.add "IF NOT EXISTS "
  result.add "idx_"
  result.add T.tableName
  result.add "_"
  result.add params.join("_")
  result.add " ON "
  result.add T.tableNameQuoted
  result.add "("
  result.add params.join(", ")
  result.add ")"

template withTransaction*(db: Db, body) =
  # Start a transaction
  discard db.query("BEGIN;")

  try:
    body

    # Commit the transaction
    discard db.query("COMMIT;")
  except Exception as e:
    discard db.query("ROLLBACK;")
    raise e

proc sqlDumpHook*(data: Bytes): string =
  let hexChars = "0123456789abcdef"
  var hexStr = "\\x"
  for ch in data.string:
    let code = ch.ord
    hexStr.add hexChars[code shr 4]  # Dividing by 16
    hexStr.add hexChars[code and 0x0F]  # Modulo operation with 16
  return hexStr

proc hexNibble(ch: char): int =
  case ch:
  of '0'..'9':
    return ch.ord - '0'.ord
  of 'a'..'f':
    return ch.ord - 'a'.ord + 10
  of 'A'..'F':
    return ch.ord - 'A'.ord + 10
  else:
    raise newException(DbError, "Invalid hexadecimal digit: " & $ch)

proc sqlParseHook*(data: string, v: var Bytes) =
  if not (data.len >= 2 and data[0] == '\\' and data[1] == 'x'):
    raise newException(DbError, "Invalid binary representation" )
  var buffer = ""
  for i in countup(2, data.len - 1, 2):  # Parse the hexadecimal characters two at a time
    let highNibble = hexNibble(data[i])  # Extract the high nibble
    let lowNibble = hexNibble(data[i + 1])  # Extract the low nibble
    let byte = (highNibble shl 4) or lowNibble  # Convert the high and low nibbles to a byte
    buffer.add chr(byte)  # Convert the byte to a character and append it to the result string
  v = buffer.Bytes
