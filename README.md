# Debby: An Opinionated ORM for Nim

`nimble install debby`

![Github Actions](https://github.com/treeform/debby/workflows/Github%20Actions/badge.svg)

[API reference](https://treeform.github.io/debby)

This library depends on:
  * jsony

> Note: Debby is still in its early stages. We appreciate your feedback and contributions!

Debby is a powerful, intuitive, and opinionated Object-Relational Mapping (ORM) library designed specifically for Nim. Built with simplicity and efficiency in mind, Debby allows you to interact with your databases.

With Debby, you can define models as plain Nim objects, perform CRUD operations, handle migrations, and even create complex queries with a type-safe, Nim-like filter syntax.

- **Powerful ORM**: Create, Read, Update, and Delete operations are simple and intuitive.
- **Nim-like filter syntax**: Write SQL filters as you would write Nim code!
- **Nim-centric Model Definition**: Define your database schema using the familiar syntax and type system of Nim.
- **JSON fields**: Automatically converts complex fields to JSON and back.
- **Custom queries and object mapping**: Supports custom SQL queries and maps them to plain Nim objects.
- **Database Migrations**: Detects schema changes and aids in the generation of migration scripts based on your Nim models.

Whether you're building a small project or a large-scale application, Debby aims to make your experience with databases in Nim as efficient and enjoyable as possible.

**Supported Databases**: SQLite, PostgreSQL, MySql.

## Quick Start

```nim
let db = openDatabase("auto.db")

type Auto = ref object
  id: int
  make: string
  model: string
  year: int

db.createTable(Auto)

var auto = Auto(
  make: "Chevrolet",
  model: "Camaro Z28",
  year: 1970
)
db.insert(auto)                 # Create
auto = db.get(Auto, auto.id)    # Read
auto.year = 1971
db.update(auto)                 # Update
db.delete(auto)                 # Delete
```

# Table Creation and Indexes

Define your database models as plain Nim objects:
```nim
type Auto = ref object
  id: int       ## Special primary-key field, required!!!
  make: string
  model: string
  year: int
```

The only required fields is the `.id` field. It must always be `int` and can't be changed. Debby uses the `.id` field for most operations.

Debby makes it easy to create indices on your tables to speed up queries:

```nim
db.createIndex(Auto, "make")
db.createIndex(Auto, "model", "model")
db.createIndex(Auto, "model", "model", "year")
```

Remember to add an index when you are going to be querying based on that field or set of fields often.

# The CRUD part:

Lets insert autos into the database. You can insert one items at a time:

```nim
let auto = Auto(
  make: "Chevrolet",
  model: "Camaro Z28",
  year: 1970
)
db.insert(auto)
```

When inserting debby updates the `.id` of the object just inserted.

```nim
echo auto.id
```

You can also insert whole seq of objects at at time:

```nim
db.insert(@[
    Auto(make: "Chevrolet", model: "Camaro Z28", year: 1970),
    Auto(make: "Porsche", model: "911 Carrera RS", year: 1973),
    Auto(make: "Lamborghini", model: "Countach", year: 1974),
])
```

Once you know the `.id` of the object you can read the data back using `get()`:

```nim
var car = db.get(Auto, id: 1)
```

You can get multiple objects using `filter()` using a type-safe query builder:

```nim
let cars = db.filter(Auto, it.year > 1990)
```

With `filter()` you can perform complex queries even with logical operators:

```nim
let cars = db.filter(Auto, it.make == "Ferrari" or it.make == "Lamborghini")
doAssert cars.len == 3
```

To save changes you've made to your objects back to the database, just call `db.update` with the objects:

```nim
db.update(car)
```

Just make sure that the `.id` fields is set. Debby uses this special field for all operations.

Just like you can `insert()` multiple objects in a seq, you can `update()` them too:

```nim
db.update(@[car1, car2, car])
```

Some times you are not sure if you need to update or create an row. For that you can use `upsert()` and it will update or insert:

```nim
db.upsert(car)
db.upsert(@[car1, car2, car])
```

Again the `.id` field is crucial, if its `0` debby will `insert()`, otherwise it will `update()`.

## Transactions

You can use `withTransaction()` block to make sure to update or insert everything at once:

```nim
db.withTransaction:
  let p1 = Payer(name: "Bar")
  db.insert(p1)
  db.insert(Card(payerId: p1.id, number: "1234.1234"))
```

If an exception happens during a transaction it will be rolled back.

## Custom SQL queries

Debby also supports custom SQL queries with parameters. Use the `db.query()` function to perform queries:

```nim
db.query("select 5")
```

Don't splice arguments into the SQL queries as it can cause SQL injection attacks. Rather use the `?` substitution placeholder.

```nim
db.query("select ?", 5)
```

By default `db.query` returns simple `seq[seq[string]]` which corresponds to rows and columns. The results can be ignored when you don't expect any results.

## Mapping SQL queries to objects.

A cool power of debby comes from mapping custom SQL queries to any `ref object`. Just pass the object type you want to map as first argument to `query()`.

```nim
type SteamPlayer = ref object
  id: int
  steamId: uint64
  rank: float32
  name: string

let players = db.query(SteamPlayer, "SELECT * FROM steam_player WHERE name = ?", "foo")
```

For big heavy objects, you can select a subset of fields and map them to a different smaller `ref objects`.

```nim
type RankName = ref object
  rank: float32
  name: string
let players = db.query(RankName, "SELECT name, rank FROM steam_player WHERE name = ?", "foo")
```

This can also be used for custom rows computed entirely on the fly:

```nim
type CountYear = ref object
  count: int
  year: int
let rows = db.query(CountYear, "SELECT count(*) as count, year FROM auto GROUP BY year")
```

## JSON Fields

Debby can map almost any plain Nim object to SQL and back. If the object field is a complex type. It will turn into JSON field serialized using [jsony](https://github.com/treeform/jsony).

```nim
type Location = ref object
  id: int
  name: string
  revenue: Money
  position: Vec2
  items: seq[string]
  rating: float32
```

| id | name | revenue | position | items | rating |
| -- | ---- | ------- | -------- | ----- | ------ |
| 1 | Super Cars | 1234 | {"x":123.0,"y":456.0} | ["wrench","door","bathroom"] | 1.5

This means you can create and use many Nim objects as is, and save and load them from the database with minimal changes.

Many DBs have JSON functions to operate on JSON stores in the rows this way.

## sqlParseHook / sqlDumpHook

If JSON encoding with jsony is not enough, you can define custom `sqlParseHook()` and `sqlDumpHook()` for your field types.

```nim
type Money = distinct int64

proc sqlDumpHook(v: Money): string =
  result = "$" & $v.int64 & "USD"

proc sqlParseHook(data: string, v: var Money) =
  v = data[1..^4].parseInt().Money
```

It will store money as string:

```$1234USD```

## Check table.

As you initialize your data base you should run `checkTable()` on all of your tables.

```nim
type CheckEntry = ref object
  id: int
  toField: string
  money: Money

db.checkTable(CheckEntry)
```

Check table wil cause an exception if your schema defined with Nim does not match the schema defined in SQL. It will even suggest the SQL command to run to bring your schema up to date.

```
Field cars.msrp is missing
Add it with:
ALTER TABLE cars ADD msrp REAL;
Or compile --d:debbyYOLO to do this automatically
```

Yes using `--d:debbyYOLO` can do this automatically, but it might **not** be what you want! Always be vigilant.
