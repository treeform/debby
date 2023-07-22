## Public interface to you library.

import std/strutils, std/tables, std/sequtils, std/macros, std/parseutils,
    std/typetraits, jsony, common, std/sets, std/strformat

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

proc dbError*(db: Db) {.noreturn.} =
  raise newException(DbError, "SQLite: " & $sqlite3_errmsg(db))

proc openDatabase*(path: string): Db =
  var db: Db
  if sqlite3_open(path, db) == SQLITE_OK:
    result = db
  else:
    dbError(db)

proc close*(db: Db) =
  if sqlite3_close(db) != SQLITE_OK:
    dbError(db)

proc prepareQuery(
  db: Db,
  query: string,
  args: varargs[string]
): Statement =
  ## Formats and prepares the statement.

  if query.count('?') != args.len:
    dbError("Number of arguments and number of ? in query does not match")

  if sqlite3_prepare_v2(db, query.cstring, query.len.cint, result, nil) != SQLITE_OK:
    dbError(db)
  for i, arg in args:
    if arg.len == 0:
      continue
    if sqlite3_bind_text(result, int32(i + 1), arg[0].unsafeAddr, arg.len.int32, nil) != SQLITE_OK:
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
  args: varargs[string, `$`]
): seq[Row] {.discardable.} =
  ## Queries the DB.
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

proc tableExists*[T](db: Db, t: typedesc[T]): bool =
  ## Checks if table exists.
  for x in db.query(
      "SELECT name FROM sqlite_master WHERE type='table' and name = ?",
      T.tableName
    ):
    result = x[0] == T.tableName

proc dropTable*[T](db: Db, t: typedesc[T]) =
  ## Removes tables, errors out if it does not exist.
  db.query("DROP TABLE " & T.tableName)

proc dropTableIfExists*[T](db: Db, t: typedesc[T]) =
  ## Removes tables if it exists.
  db.query("DROP TABLE IF EXISTS " & T.tableName)

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
    for x in db.query("PRAGMA table_info(" & T.tableName & ")"):
      let
        fieldName = x[1]
        fieldType = x[2]
        notNull = x[3] == "1"
        defaultValue = x[4]
        primaryKey = x[5]  == "1"

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
  result.add "("
  result.add params.join(", ")
  result.add ")"

proc query*[T](
  db: Db,
  t: typedesc[T],
  query: string,
  args: varargs[string, `$`]
): seq[T] =

  let tmp = T()

  var
    statement = prepareQuery(db, query, args)
    columnCount = sqlite3_column_count(statement)
    headerIndex: seq[int]
  for i in 0 ..< columnCount:
    let columnName = sqlite3_column_name(statement, i)
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

proc insert*[T: ref object](db: Db, obj: T) =
  ## Inserts the object into the database.
  discard db.insertInner(obj)
  obj.id = db.sqlite3_last_insert_rowid().int

template withTransaction*(db: Db, body) =
  # Start a transaction
  discard db.query("BEGIN TRANSACTION;")

  try:
    body

    # Commit the transaction
    discard db.query("COMMIT;")
  except Exception as e:
    discard db.query("ROLLBACK;")
    raise e
