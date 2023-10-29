import debby/sqlite

type App = object
  database: Db

var app = App()
app.database = sqlite.openDatabase(
  path = "tests/test.db"
)

# Test with basic object
type Auto = ref object
  id: int
  make: string
  model: string
  year: int

app.database.dropTableIfExists(Auto)
app.database.createTable(Auto)

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
app.database.insert(vintageSportsCars)

let cars = app.database.filter(Auto, it.year > 1990)
doAssert cars.len == 2
