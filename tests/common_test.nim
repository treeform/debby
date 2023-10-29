import std/strutils

block:
  # Test the most basic operation:
  doAssert db.query("select 5") == @[@["5"]]

block:
  let rows = db.query("select ?", "hello world")
  doAssert rows.len == 1
  let row = rows[0]
  doAssert row[0] == "hello world"

block:
  let rows = db.query("select ?, ?, ?", "hello", " ", "world")
  doAssert rows.len == 1
  let row = rows[0]
  doAssert row[0] == "hello"
  doAssert row[1] == " "
  doAssert row[2] == "world"

block:
  # Test fetching current date
  let currDate = db.query("select CURRENT_DATE")[0][0]
  for row in db.query("select ?", currDate):
    doAssert row[0] == currDate

# Test with basic object
type Auto = ref object
  id: int
  make: string
  model: string
  year: int
  truck: bool

var vintageSportsCars = @[
  Auto(make: "Chevrolet", model: "Camaro Z28", year: 1970),
  Auto(make: "Porsche", model: "911 Carrera RS", year: 1973),
  Auto(make: "Lamborghini", model: "Countach", year: 1974),
  Auto(make: "Ferrari", model: "308 GTS", year: 1977),
  Auto(make: "Aston Martin", model: "V8 Vantage", year: 1977),
  Auto(make: "Datsun", model: "280ZX", year: 1980),
  Auto(make: "Ferrari", model: "Testarossa", year: 1984),
  Auto(make: "BMW", model: "M3", year: 1986),
  Auto(make: "Mazda", model: "RX-7", year: 1993),
  Auto(make: "Toyota", model: "Supra", year: 1998)
]

db.dropTableIfExists(Auto)
db.checkTable(Auto)
db.insert(vintageSportsCars)

block:
  # Test empty filter (all filter).
  doAssert db.filter(Auto).len == 10

block:
  # Test simple filters >
  let cars = db.filter(Auto, it.year > 1990)
  doAssert cars.len == 2

block:
  # Test simple filters with equals
  let model = "Countach"
  let cars = db.filter(Auto, it.model == model)
  doAssert cars.len == 1

block:
  # test filters with or
  let cars = db.filter(Auto, it.make == "Ferrari" or it.make == "Lamborghini")
  doAssert cars.len == 3

block:
  # Test filter with <
  let cars = db.filter(Auto, it.year < 1980)
  doAssert cars.len == 5

block:
  # Test filter with !=
  let model = "M3"
  let cars = db.filter(Auto, it.model != model)
  doAssert cars.len == 9

block:
  # Test filter with multiple conditions
  let cars = db.filter(Auto, it.make == "Ferrari" and it.year > 1980)
  doAssert cars.len == 1

block:
  # Test filters with complex or conditions
  let cars = db.filter(Auto, (it.make == "BMW" or it.make == "Toyota") and it.year < 2000)
  doAssert cars.len == 2

block:
  # Test filters with complex and conditions
  let cars = db.filter(Auto, it.year < 1980 and (it.make == "Ferrari" or it.make == "Lamborghini"))
  doAssert cars.len == 2

block:
  # Test filters with not
  let cars = db.filter(Auto, not(it.make == "Ferrari"))
  doAssert cars.len == 8

block:
  # Test filter for cars made after 1990s with specific manufacturers
  let cars = db.filter(Auto, it.year > 1990 and (it.make == "BMW" or it.make == "Mazda" or it.make == "Toyota"))
  doAssert cars.len == 2

block:
  # Test filter for cars with year in a specific range
  let cars = db.filter(Auto, it.year >= 1970 and it.year <= 1980)
  doAssert cars.len == 6

block:
  # Test filter with combination of not and or
  let cars = db.filter(Auto, not(it.make == "BMW" or it.make == "Toyota"))
  doAssert cars.len == 8

block:
  # Test filter with combination of not and and
  let cars = db.filter(Auto, not(it.make == "Ferrari" and it.year < 1980))
  doAssert cars.len == 9

block:
  # Test filter with invalid function call
  proc isOfYear(a: Auto): bool = a.year >= 1980

  let res = compiles:
    let cars = db.filter(Auto, it.isOfYear())

  doAssert not res, "`it` passed to function compiles when it shouldn't!"

  proc nest1(a: Auto): Auto = a
  proc nest2(a: Auto): bool = a.year >= 1980
  let res2 = compiles:
    let cars = db.filter(Auto, nest2(nest1(it)))

  doAssert not res, "`it` passed to a nested function compiles when it shouldn't!"

block:
  # Test update
  let startYear = 1970
  let endYear = 1980
  let cars = db.filter(Auto, it.year >= startYear and it.year < endYear)
  doAssert cars.len == 5
  db.update(cars)

block:
  # Test filter with function call.
  proc startYear(): int = 1980
  let cars = db.filter(Auto, it.year >= startYear())
  doAssert cars.len == 5

  let cars2 = db.filter(Auto, it.year >= parseInt("1980"))
  doAssert cars2.len == 5

  let cars3 = db.filter(Auto, it.year >= parseInt("19" & "80"))
  doAssert cars3.len == 5

block:
  # Test upsert
  vintageSportsCars.add Auto(
    make: "Jeep",
    model: "Wrangler",
    year: 1993,
    truck: true)
  db.upsert(vintageSportsCars)
  doAssert db.filter(Auto).len == 11

  let jeeps = db.filter(Auto, it.make == "Jeep" and it.model == "Wrangler")
  doAssert jeeps[0].truck == true

block:
  # Test uint64 field as main field.
  type SteamPlayer = ref object
    id: int
    steamId: uint64
    name: string

  db.dropTableIfExists(SteamPlayer)
  db.createTable(SteamPlayer)

  db.insert(SteamPlayer(steamId: uint64.high, name:"Foo"))

  var steamPlayers = db.query(
    SteamPlayer,
    "select * from steam_player where steam_id = ?",
    uint64.high
  )
  doAssert steamPlayers[0].name == "Foo"
  doAssert steamPlayers[0].steamId == uint64.high

  steamPlayers[0].name = "NewName"
  db.update(steamPlayers[0])

  steamPlayers = db.query(
    SteamPlayer,
    "select * from steam_player where steam_id = ?",
    uint64.high
  )
  doAssert steamPlayers[0].name == "NewName"
  doAssert steamPlayers[0].steamId == uint64.high

  db.delete(steamPlayers[0])
  steamPlayers = db.query(
    SteamPlayer,
    "select * from steam_player where steam_id = ?",
    uint64.high
  )
  doAssert steamPlayers.len == 0

block:
  # Test string field as main field.
  type Push = ref object
    id: int
    iden: string
    bodyText: string

  db.dropTableIfExists(Push)
  db.createTable(Push)

  db.insert(Push(iden: "uuid:XXXX", bodyText:"Hi, you there?"))

  var pushes = db.query(
    Push,
    "select * from push where iden = ?",
    "uuid:XXXX"
  )
  doAssert pushes[0].bodyText == "Hi, you there?"
  doAssert pushes[0].iden == "uuid:XXXX"

  pushes[0].bodyText = "new text"
  db.update(pushes)

  pushes = db.query(
    Push,
    "select * from push where iden = ?",
    "uuid:XXXX"
  )
  doAssert pushes[0].bodyText == "new text"
  db.delete(pushes)

block:
  # Test read and write Binary data.
  type FileEntry = ref object
    id: int
    fileName: string
    data: Bytes

  db.dropTableIfExists(FileEntry)
  db.createTable(FileEntry)

  let zeroBin = "" & char(0x00)
  db.insert FileEntry(
    fileName: "zero.bin",
    data: zeroBin.Bytes
  )
  doAssert db.get(FileEntry, 1).data.string == zeroBin

  let unicodeBadBin = char(0xC3) & char(0x28)
  db.insert FileEntry(
    fileName: "unicodebad.bin",
    data: unicodeBadBin.Bytes
  )
  doAssert db.get(FileEntry, 2).data.string == unicodeBadBin

block:
  # Test transactions
  type Payer = ref object
    id: int
    name: string
  db.dropTableIfExists(Payer)
  db.createTable(Payer)

  type Card = ref object
    id: int
    payerId: int
    number: string
  db.dropTableIfExists(Card)
  db.createTable(Card)

  db.withTransaction:
    let
      p1 = Payer(name:"Bar")
      p2 = Payer(name:"Baz")
    db.insert(p1)
    db.insert(p2)
    db.insert(Card(payerId:p1.id, number:"1234.1234"))

block:
  # Test auto JSON fields.
  type
    Vec2 = object
      x: float32
      y: float32
    Money = distinct int64 # money in cents

  type Location = ref object
    id: int
    name: string
    revenue: Money
    position: Vec2
    items: seq[string]
    rating: float32

  db.dropTableIfExists(Location)
  db.createTable(Location)

  db.insert Location(
    name: "Super Cars",
    revenue: 1234.Money,
    position: Vec2(x:123, y:456),
    items: @["wrench", "door", "bathroom"],
    rating: 1.5
  )

  let loc = db.get(Location, 1)
  doAssert loc.name == "Super Cars"
  doAssert loc.revenue.int == (1234.Money).int
  doAssert loc.position == Vec2(x:123, y:456)
  doAssert loc.items == @["wrench", "door", "bathroom"]
  doAssert loc.rating == 1.5

block:
  # Test invalid table creates.

  # id must always be there
  type BadTable1 = ref object
    iden: string

  db.dropTableIfExists(BadTable1)
  doAssertRaises(DbError):
    db.createTable(BadTable1)

  # id must always be integer
  type BadTable2 = ref object
    id: string

  db.dropTableIfExists(BadTable2)
  doAssertRaises(DbError):
    db.createTable(BadTable2)

  # can't use reserved words as table names
  type BadTable3 = ref object
    id: int
    select: int
    where: string
    group: float32

  db.dropTableIfExists(BadTable3)
  doAssertRaises(DbError):
    db.createTable(BadTable3)

  type User = ref object
    id: int
    name: string

  doAssertRaises(DbError):
    db.createTable(User)

  doAssertRaises(DbError):
    # Count ? of does not match arg count.
    db.query("select ?, ?", "hello world")

  doAssertRaises(DbError):
    # Count ? of does not match arg count.
    db.query("select ?", "hello", "world")

  # Test nested ?
  for row in db.query("select ?", "? ?"):
    doAssert row == @["? ?"]

# Text sqlDumpHook/sqlParseHook (can't be in a block)
type
  Money = distinct int64

type CheckEntry = ref object
  id: int
  toField: string
  money: Money

proc sqlDumpHook(v: Money): string =
  result = "\"$" & $v.int64 & "USD\""

proc sqlParseHook(data: string, v: var Money) =
  v = data[2..^5].parseInt().Money

db.dropTableIfExists(CheckEntry)
db.createTable(CheckEntry)
db.checkTable(CheckEntry)

db.insert CheckEntry(
  toField: "Super Cars",
  money: 1234.Money
)

let check = db.get(CheckEntry, 1)
doAssert check.id == 1
doAssert check.toField == "Super Cars"
doAssert check.money.int == 1234.Money.int

db.update(check)
db.upsert(check)
check.id = 0
db.upsert(check)
db.delete(check)
