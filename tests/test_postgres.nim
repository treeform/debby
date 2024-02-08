import debby/postgres

let db = openDatabase(
  host = "localhost",
  user = "testuser",
  password = "test",
  database = "test"
)

include common_test

block:
  # Test PG unique constraint

  type
    UniqueName = ref object
      id: int
      name: string

  db.dropTableIfExists(UniqueName)
  db.createTable(UniqueName)

  db.query("CREATE UNIQUE INDEX unique_name_idx ON unique_name (name)")

  echo "at the unique constraint"
  db.insert(UniqueName(name: "hello"))
  doAssertRaises(DbError):
    db.insert(UniqueName(name: "hello"))
  echo "done unique constraint"

block:
  # Test PG wrong type

  type
    WrongType = ref object
      id: int
      num: int
      name: string

  db.dropTableIfExists(WrongType)
  db.createTable(WrongType)

  echo "at the wrong type:"
  doAssertRaises(DbError):
    db.query(
      "INSERT INTO wrong_type (num, name) VALUES (?,?)",
      "hello",
      123
    )
  echo "done wrong type"

echo "close"
db.close()
