import debby/sqlite, debby/pools, mummy, mummy/routers, std/strutils,
    std/strformat, webby

let pool = newPool()

var adminObjectList: seq[string]

const
  HtmlHeader = """
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Admin</title>
    <link rel="stylesheet" href="/admin.css">
</head>
<body>
"""
  HtmlFooter = """
</body>
"""

proc cssHandler(request: Request) =
  var headers: HttpHeaders
  headers["Content-Type"] = "text/css"
  request.respond(200, headers, readFile("examples/admin.css"))

proc adminHandler(request: Request) =
  # Generate the HTML for listing all T.
  var x = HtmlHeader
  x.add &"<h1>Debby Admin</h1>"

  x.add "<p>"
  x.add "<a href='/admin'>admin</a>"
  x.add "</p>"

  x.add "<table>"

  {.gcsafe.}:
    for objName in adminObjectList:
      x.add "<tr>"
      x.add &"<td><a href='/admin/" & objName.toLowerAscii() & "'>" & objName & "</a></td>"
      x.add "</tr>"
    x.add "</table>"

  x.add HtmlFooter

  var headers: HttpHeaders
  headers["Content-Type"] = "text/html"
  request.respond(200, headers, x)

proc listHandler[T](request: Request) =
  # Generate the HTML for listing all T.
  var x = HtmlHeader
  x.add &"<h1>{$T} Listing</h1>"

  x.add "<p>"
  x.add "<a href='/admin'>admin</a> &raquo; "
  x.add $T
  x.add "</p>"

  x.add "<table>"
  var tmp: T
  x.add "<tr>"
  for fieldName, value in tmp[].fieldPairs:
    x.add "<th>" & fieldName & "</th>"
  x.add "</tr>"

  for row in pool.filter(T):
    x.add "<tr>"
    for fieldName, value in row[].fieldPairs:
      if fieldName == "id":
        x.add &"<td><a href='/admin/" & ($T).toLowerAscii() & "/" & $value & "'>" & $value & "</a></td>"
      else:
        x.add "<td>" & $value & "</td>"
    x.add "</tr>"
  x.add "</table>"

  x.add "<form method='get' action='" & ($T).toLowerAscii() & "/new'>"
  x.add "<br><button>New</button>"
  x.add "<form>"

  x.add HtmlFooter

  var headers: HttpHeaders
  headers["Content-Type"] = "text/html"
  request.respond(200, headers, x)

proc itemHandler[T](request: Request) =
  # Generate the HTML for specific object.
  var x = HtmlHeader
  let id = request.uri.rsplit("/", maxSplit = 1)[^1].parseInt()
  let obj = pool.get(T, id)

  x.add &"<h1>{$T}</h1>"

  x.add "<p>"
  x.add "<a href='/admin'>admin</a> &raquo; "
  x.add "<a href='/admin/" & $($T).toLowerAscii() & "'>" & $T & "</a> &raquo; "
  x.add $obj.id
  x.add "</p>"

  x.add "<form method='post'>"
  x.add "<table>"
  for fieldName, value in obj[].fieldPairs:
    x.add "<tr>"
    x.add "<th>" & fieldName & "</th>"
    if fieldName == "id":
      x.add "<td><strong>" & $value & "</strong></td>"
    elif type(value) isnot string:
      x.add "<td><input name='" & fieldName & "' value='" & $value & "'></td>"
    else:
      x.add "<td><textarea name='" & fieldName & "'>" & $value & "</textarea></td>"
    x.add "</tr>"
  x.add "</table>"

  x.add "<br><button submit=true name='action' value='save'>Save</button>"
  x.add " <button style='background-color:var(--error); float:right' submit=true name='action' value='delete'>Delete</button>"
  x.add "</form>"

  x.add HtmlFooter

  var headers: HttpHeaders
  headers["Content-Type"] = "text/html"
  request.respond(200, headers, x)

proc saveHandler[T](request: Request) =
  # Generate the HTML for specific object.
  var x = ""
  let id = request.uri.rsplit("/", maxSplit = 1)[^1].parseInt()
  let obj = pool.get(T, id)
  let url = parseUrl(request.body)

  if url.query["action"] == "delete":
    pool.delete(obj)
  else:
    for fieldName, value in obj[].fieldPairs:
      if fieldName == "id":
        discard
      else:
        sqlParseHook(url.query[fieldName], value)
    pool.update(obj)

  var headers: HttpHeaders
  headers["Location"] = "/admin/" & $($T).toLowerAscii()
  request.respond(302, headers, x)

proc newHandler[T](request: Request) =
  # Generate the HTML for specific object.
  # Generate the HTML for specific object.
  var x = HtmlHeader

  let obj = new(T)

  x.add &"<h1>{$T}</h1>"

  x.add "<p>"
  x.add "<a href='/admin'>admin</a> &raquo; "
  x.add "<a href='/admin/" & $($T).toLowerAscii() & "'>" & $T & "</a> &raquo; "
  x.add "new"
  x.add "</p>"

  x.add "<form method='post'>"
  x.add "<table>"
  for fieldName, value in obj[].fieldPairs:
    x.add "<tr>"
    x.add "<th>" & fieldName & "</th>"
    if fieldName == "id":
      x.add "<td><strong>new</strong></td>"
    elif type(value) isnot string:
      x.add "<td><input name='" & fieldName & "' value='" & $value & "'></td>"
    else:
      x.add "<td><textarea name='" & fieldName & "'>" & $value & "</textarea></td>"
    x.add "</tr>"
  x.add "</table>"

  x.add "<br><button submit=true>Create</button>"
  x.add "</form>"

  x.add HtmlFooter

  var headers: HttpHeaders
  headers["Content-Type"] = "text/html"
  request.respond(200, headers, x)

proc createHandler[T](request: Request) =
  # Generate the HTML for specific object.
  var x = ""
  let obj = new(T)
  let url = parseUrl(request.body)
  for fieldName, value in obj[].fieldPairs:
    if fieldName == "id":
      discard
    else:
      sqlParseHook(url.query[fieldName], value)
  pool.insert(obj)

  var headers: HttpHeaders
  headers["Location"] = "/admin/" & $($T).toLowerAscii()
  request.respond(302, headers, x)

# Set up a mummy router
var router: Router
router.get("/admin.css", cssHandler)
router.get("/admin", adminHandler)

proc addAdmin(t: typedesc) =

  adminObjectList.add($t)

  router.get("/admin/" & ($t).toLowerAscii(), listHandler[t])

  router.get("/admin/" & ($t).toLowerAscii() & "/new", newHandler[t])
  router.post("/admin/" & ($t).toLowerAscii() & "/new", createHandler[t])

  router.get("/admin/" & ($t).toLowerAscii() & "/*", itemHandler[t])
  router.post("/admin/" & ($t).toLowerAscii() & "/*", saveHandler[t])





for i in 0 ..< 10:
  pool.add(openDatabase("examples/admin.db"))

type Account = ref object
  id: int
  name: string
  bio: string

type Post = ref object
  id: int
  accountId: int
  authorId: int
  title: string
  tags: string
  postDate: string
  body: string
  views: int
  rating: float32

type Comment = ref object
  id: int
  postId: int
  authorId: int
  postDate: string
  body: string
  views: int
  rating: float32

# In order to use a pool, call `withDb:`, this will inject a `db` variable so
# that you can query a db. It will return the db back to the pool after.
# This is great if you are going to be making many database operations
pool.withDb:
  if not db.tableExists(Account):
    # When running this for the first time, it will create the table
    # and populate it with dummy data.
    db.createTable(Account)
    db.insert(Account(
      name: "root",
      bio: "This is the root account"
    ))

  if not db.tableExists(Post):
    # When running this for the first time, it will create the table
    # and populate it with dummy data.
    db.createTable(Post)
    db.insert(Post(
      title: "First post!",
      authorId: 1,
      tags: "autogenerated, system",
      postDate: "today",
      body: "This is how to create a post"
    ))
    db.insert(Post(
      title: "Second post!",
      authorId: 1,
      tags: "autogenerated, system",
      postDate: "yesterday",
      body: "This is how to create a second post"
    ))

  if not db.tableExists(Comment):
    # When running this for the first time, it will create the table
    # and populate it with dummy data.
    db.createTable(Comment)
    db.insert(Comment(
      postId: 1,
      authorId: 1,
      postDate: "today",
      body: "This is how to create a comment"
    ))

pool.checkTable(Account)
pool.checkTable(Post)
pool.checkTable(Comment)

addAdmin(Account)
addAdmin(Post)
addAdmin(Comment)

# Set up mummy server
let server = newServer(router)
echo "Serving on http://localhost:8080"
server.serve(Port(8080))
