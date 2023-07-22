import debby/mysql

let db = openDatabase(
  host = "127.0.0.1",
  user = "root",
  database = "test_db",
  password = "hunter2",
  port = 3306
)

include common_test

db.close()
