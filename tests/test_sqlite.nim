import debby/sqlite

{.define: debbyTestSqlite.}

let db = openDatabase("tests/test.db")

include common_test

db.close()
