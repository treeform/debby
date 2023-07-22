when defined(nimdoc):
  ## Used to generate docs.
  import debby/sqlite
else:
  {.error: "Import debby/sqlite, debby/postgres, or debby/mysql".}
