import common, jsony, std/strutils, std/strformat, std/tables, std/macros,
    std/sets
export common, jsony

when defined(windows):
  const Lib = "(libmysql.dll|libmariadb.dll)"
elif defined(macosx):
  const Lib = "(libmysqlclient|libmariadbclient)(|.21|).dylib"
else:
  const Lib = "(libmysqlclient|libmariadbclient).so(|.21|)"

# ?

type
  PRES = pointer

  FIELD*{.final.} = object
    name*: cstring
  PFIELD* = ptr FIELD

{.push importc, cdecl, dynlib: Lib.}

proc mysql_init*(MySQL: DB): DB

proc mysql_error*(MySQL: DB): cstring

proc mysql_real_connect*(
  MySQL: DB,
  host: cstring,
  user: cstring,
  passwd: cstring,
  db: cstring,
  port: cuint,
  unix_socket: cstring,
  clientflag: int
): DB

proc mysql_close*(sock: DB)

proc mysql_query*(MySQL: DB, q: cstring): cint

proc mysql_store_result*(MySQL: DB): PRES

proc mysql_num_rows*(res: PRES): uint64

proc mysql_num_fields*(res: PRES): cuint

proc mysql_fetch_row*(result: PRES): cstringArray

proc mysql_free_result*(result: PRES)

proc mysql_real_escape_string*(MySQL: DB, fto: cstring, `from`: cstring, len: int): int

proc mysql_insert_id*(MySQL: DB): uint64

proc mysql_fetch_field_direct*(res: PRES, fieldnr: cuint): PFIELD

{.pop.}

proc dbError*(db: Db) {.noreturn.} =
  raise newException(DbError, "MySQL: " & $mysql_error(db))

proc prepareQuery(
  db: DB,
  query: string,
  args: varargs[string]
): string =
  ## Formats and prepares the statement.
  when defined(debbyShowSql):
    debugEcho(query)

  if query.count('?') != args.len:
    dbError("Number of arguments and number of ? in query does not match")

  var argNum = 0
  for c in query:
    if c == '?':
      result.add "'"
      let arg = args[argNum]
      var escapedArg = newString(arg.len * 2 + 1)
      let newLen = mysql_real_escape_string(
        db,
        escapedArg.cstring,
        arg.cstring,
        arg.len.int32
      )
      escapedArg.setLen(newLen)
      result.add escapedArg
      result.add "'"
      inc argNum
    else:
      result.add c

proc readRow(res: PRES, r: var seq[string], columnCount: int) =
  ## Reads a single row back.
  var row = mysql_fetch_row(res)
  for column in 0 ..< columnCount:
    r[column] = $row[column]

proc query*(
  db: DB,
  query: string,
  args: varargs[string, `$`]
): seq[Row] {.discardable.} =
  ## Queries the DB.
  var sql = prepareQuery(db, query, args)
  if mysql_query(db, sql.cstring) != 0:
    dbError(db)
  var res = mysql_store_result(db)
  if res != nil:
    var rowCount = mysql_num_rows(res).int
    var columnCount = mysql_num_fields(res).int
    try:
      for i in 0 ..< rowCount:
        var row = newSeq[string](columnCount)
        readRow(res, row, columnCount)
        result.add(row)
    finally:
      mysql_free_result(res)

proc openDatabase*(
    database: string,
    host = "localhost",
    port = 3306,
    user = "root",
    password = ""
): DB =
  ## opens a database connection. Raises `EDb` if the connection could not
  ## be established.
  var db = mysql_init(nil)
  if db == nil:
    dbError("could not open database connection")

  if mysql_real_connect(
    db,
    host.cstring,
    user.cstring,
    password.cstring,
    database.cstring,
    port.cuint,
    nil,
    0
  ) == nil:
    dbError(db)

  db.query("SET sql_mode='ANSI_QUOTES'")

  return db

proc close*(db: DB) =
  ## closes the database connection.
  mysql_close(db)

proc dropTableIfExists*[T](db: Db, t: typedesc[T]) =
  ## Removes tables if it exists.
  db.query("DROP TABLE IF EXISTS " & T.tableName)

proc tableExists*[T](db: Db, t: typedesc[T]): bool =
  ## Checks if table exists.
  for row in db.query(&"""SELECT
    table_name
FROM
    information_schema.tables
WHERE
    table_schema = DATABASE()
    AND table_name = '{T.tableName}';
"""):
    result = true
    break

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
  result.add T.tableName
  result.add " ("
  result.add params.join(", ")
  result.add ")"

proc sqlType(name, t: string): string =
  ## Converts nim type to sql type.
  case t:
  of "string": "text"
  of "int8": "tinyint"
  of "uint8": "tinyint unsigned"
  of "int16": "smallint"
  of "uint16": "smallint unsigned"
  of "int32": "int"
  of "uint32": "int unsigned"
  of "int", "int64": "bigint"
  of "uint", "uint64": "bigint unsigned"
  of "float", "float32": "float"
  of "float64": "double"
  of "bool": "boolean"
  of "Bytes": "text"
  else: "json"

proc createTableStatement*[T: ref object](db: Db, t: typedesc[T]): string =
  ## Given an object creates its table create statement.
  validateObj(T)
  let tmp = T()
  result.add "CREATE TABLE "
  result.add T.tableName
  result.add " (\n"
  for name, field in tmp[].fieldPairs:
    result.add "  "
    result.add name.toSnakeCase
    result.add " "
    result.add sqlType(name, $type(field))
    if name == "id":
      result.add " PRIMARY KEY AUTO_INCREMENT"
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
      issues.add "Table " & T.tableName & " does not exist."
      issues.add "Create it with:"
      issues.add db.createTableStatement(t)
  else:
    var tableSchema: Table[string, string]
    for row in db.query(&"""SELECT
      COLUMN_NAME,
      DATA_TYPE
    FROM
      INFORMATION_SCHEMA.COLUMNS
    WHERE
      TABLE_SCHEMA = DATABASE()
      AND TABLE_NAME = '{T.tableName}';
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
        let addFieldStatement = "ALTER TABLE " & T.tableName & " ADD COLUMN " & fieldName.toSnakeCase & " "  & sqlType & ";"
        if defined(debbyYOLO):
          db.query(addFieldStatement)
        else:
          issues.add "Field " & T.tableName & "." & fieldName & " is missing"
          issues.add "Add it with:"
          issues.add addFieldStatement

  if issues.len != 0:
    issues.add "Or compile --d:debbyYOLO to do this automatically"
    raise newException(DBError, issues.join("\n"))

proc insert*[T: ref object](db: Db, obj: T) =
  ## Inserts the object into the database.
  discard db.insertInner(obj)
  obj.id = mysql_insert_id(db).int

proc query*[T](
  db: Db,
  t: typedesc[T],
  query: string,
  args: varargs[string, `$`]
): seq[T] =

  let tmp = T()

  var
    sql = prepareQuery(db, query, args)

  if mysql_query(db, sql.cstring) != 0:
    dbError(db)

  var res = mysql_store_result(db)
  if res != nil:

    var rowCount = mysql_num_rows(res).int
    var columnCount = mysql_num_fields(res).int
    var headerIndex: seq[int]

    for i in 0 ..< columnCount:
      let field = mysql_fetch_field_direct(res, i.cuint)
      if field == nil:
        dbError("Field is nil")
      let columnName = $field[].name
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
        readRow(res, row, columnCount)
        let tmp = T()
        var i = 0
        for fieldName, field in tmp[].fieldPairs:
          sqlParse(row[headerIndex[i]], field)
          inc i
        result.add(tmp)
    finally:
      mysql_free_result(res)

template withTransaction*(db: Db, body) =
  # Start a transaction
  discard db.query("START TRANSACTION;")

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
