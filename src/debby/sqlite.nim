## Public interface to you library.

import std/strutils, std/tables, std/macros, std/typetraits, jsony, common,
    std/sets, std/strformat

export jsony
export common

when defined(windows):
  when defined(cpu64):
    const Lib = "sqlite3_64.dll"
  else:
    const Lib = "sqlite3_32.dll"
elif defined(macosx):
  const Lib = "libsqlite3(|.0).dylib"
else:
  const Lib = "libsqlite3.so(|.0)"

const
  SQLITE_OK* = 0
  SQLITE_ROW* = 100

type
  Statement* = pointer

{.push importc, cdecl, dynlib: Lib.}

proc sqlite3_errmsg*(
  db: Db
): cstring

proc sqlite3_open*(
  filename: cstring,
  db: var Db
): int32

proc sqlite3_close*(
  db: Db
): int32

proc sqlite3_prepare_v2*(
  db: Db,
  zSql: cstring,
  nByte: int32,
  pStatement: var Statement,
  pzTail: ptr cstring
): int32

proc sqlite3_bind_text*(
  stmt: Statement,
  index: int32,
  text: cstring,
  size: int32,
  destructor: pointer
): int32

proc sqlite3_column_bytes*(
  stmt: Statement,
  iCol: int32
): int32

proc sqlite3_column_blob*(
  stmt: Statement,
  iCol: int32
): pointer

proc sqlite3_column_count*(
  stmt: Statement
): int32

proc sqlite3_step*(
  stmt: Statement
): int32

proc sqlite3_finalize*(
  stmt: Statement
): int32

proc sqlite3_column_name*(
  stmt: Statement,
  iCol: int32
): cstring

proc sqlite3_last_insert_rowid*(
  db: Db
): int64

{.pop.}

proc sqlType(name, t: string): string =
  ## Converts nim type to sql type.
  case t:
  of "string": "TEXT"
  of "Bytes": "TEXT"
  of "int": "INTEGER"
  of "float", "float32", "float64": "REAL"
  of "bool": "INTEGER"
  of "bytes": "BLOB"
  else: "TEXT"

proc dbError*(db: Db) {.noreturn.} =
  ## Raises an error from the database.
  raise newException(DbError, "SQLite: " & $sqlite3_errmsg(db))

proc prepareQuery(
  db: Db,
  query: string,
  args: varargs[Argument, toArgument]
): Statement =
  ## Generates the query based on parameters.

  if query.count('?') != args.len:
    dbError("Number of arguments and number of ? in query does not match")

  if sqlite3_prepare_v2(db, query.cstring, query.len.cint, result, nil) != SQLITE_OK:
    dbError(db)
  for i, arg in args:
    if arg.value.len == 0:
      continue
    if sqlite3_bind_text(
      result,
      int32(i + 1),
      arg.value.cstring,
      arg.value.len.int32, nil
    ) != SQLITE_OK:
      dbError(db)

proc readRow(statement: Statement, r: var Row, columnCount: int) =
  ## Reads a single row back.
  for column in 0 ..< columnCount:
    let sizeBytes = sqlite3_column_bytes(statement, column.cint)
    if sizeBytes > 0:
      r[column].setLen(sizeBytes) # set capacity
      copyMem(
        addr(r[column][0]),
        sqlite3_column_blob(statement, column.cint),
        sizeBytes
      )

proc query*(
  db: Db,
  query: string,
  args: varargs[Argument, toArgument]
): seq[Row] {.discardable.} =
  ## Runs a query and returns the results.
  when defined(debbyShowSql):
    debugEcho(query)
  var statement = prepareQuery(db, query, args)
  var columnCount = sqlite3_column_count(statement)
  try:
    while sqlite3_step(statement) == SQLITE_ROW:
      var row = newSeq[string](columnCount)
      readRow(statement, row, columnCount)
      result.add(row)
  finally:
    if sqlite3_finalize(statement) != SQLITE_OK:
      dbError(db)

proc openDatabase*(path: string): Db =
  ## Opens the database file.
  var db: Db
  if sqlite3_open(path, db) == SQLITE_OK:
    result = db
  else:
    dbError(db)

proc close*(db: Db) =
  ## Closes the database file.
  if sqlite3_close(db) != SQLITE_OK:
    dbError(db)

proc tableExists*[T](db: Db, t: typedesc[T]): bool =
  ## Checks if table exists.
  for x in db.query(
      "SELECT name FROM sqlite_master WHERE type='table' and name = ?",
      T.tableName
    ):
    result = x[0] == T.tableName

proc createIndexStatement*[T: ref object](
  db: Db,
  t: typedesc[T],
  ifNotExists: bool,
  params: varargs[string]
): string =
  ## Returns the SQL code need to create an index.
  result.add "CREATE INDEX "
  if ifNotExists:
    result.add "IF NOT EXISTS "
  result.add "idx_"
  result.add T.tableName
  result.add "_"
  result.add params.join("_")
  result.add " ON "
  result.add T.tableName
  result.add "("
  result.add params.join(", ")
  result.add ")"

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
      result.add " PRIMARY KEY"
      if type(field) is int:
        result.add " AUTOINCREMENT"
    result.add ",\n"
  result.removeSuffix(",\n")
  result.add "\n)"

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
    for x in db.query("PRAGMA table_info(" & T.tableName & ")"):
      let
        fieldName = x[1]
        fieldType = x[2]
        notNull {.used.} = x[3] == "1"
        defaultValue {.used.} = x[4]
        primaryKey {.used.} = x[5]  == "1"

      tableSchema[fieldName] = fieldType

    for name, field in tmp[].fieldPairs:
      let fieldName = name.toSnakeCase
      let sqlType = sqlType(fieldName, $type(field))
      if fieldName.toSnakeCase in tableSchema:
        if tableSchema[fieldName.toSnakeCase ] == sqlType:
          discard # good everything matches
        else:
          issues.add "Field " & T.tableName & "." & fieldName & " expected type " & sqlType & " but got " & tableSchema[fieldName]
          # TODO create new table with right data
          # copy old data into new table
          # delete old table
          # rename new table
      else:
        let addFieldStatement = "ALTER TABLE " & T.tableName & " ADD COLUMN " & fieldName.toSnakeCase  & " "  & sqlType
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
  ## Reads the ID of the inserted ref object back.
  discard db.insertInner(obj)
  obj.id = db.sqlite3_last_insert_rowid().int

proc query*[T](
  db: Db,
  t: typedesc[T],
  query: string,
  args: varargs[Argument, toArgument]
): seq[T] =
  ## Query the table, and returns results as a seq of ref objects.
  ## This will match fields to column names.
  ## This will also use JSONy for complex fields.
  when defined(debbyShowSql):
    debugEcho(query)

  let tmp = T()

  var
    statement = prepareQuery(db, query, args)
    columnCount = sqlite3_column_count(statement)
    headerIndex: seq[int]
  for i in 0 ..< columnCount:
    let columnName = $sqlite3_column_name(statement, i)
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
    while sqlite3_step(statement) == SQLITE_ROW:
      var row = newSeq[string](columnCount)
      readRow(statement, row, columnCount)
      let tmp = T()
      var i = 0
      for fieldName, field in tmp[].fieldPairs:
        sqlParse(row[headerIndex[i]], field)
        inc i
      result.add(tmp)
  finally:
    if sqlite3_finalize(statement) != SQLITE_OK:
      dbError(db)

template withTransaction*(db: Db, body) =
  ## Transaction block.

  # Start a transaction
  discard db.query("BEGIN TRANSACTION;")

  try:
    body

    # Commit the transaction
    discard db.query("COMMIT;")
  except Exception as e:
    discard db.query("ROLLBACK;")
    raise e

proc sqlDumpHook*(v: bool): string =
  ## SQL dump hook to convert from bool.
  if v: "1"
  else: "0"

proc sqlParseHook*(data: string, v: var bool) =
  ## SQL parse hook to convert to bool.
  v = data == "1"
