import debby/postgres

let db = openDatabase(
  host = "localhost",
  user = "testuser",
  password = "test",
  database = "test"
)

include common_test

db.close()
