# What configure.win's CMake run found and what its program printed
# (inst/zigcmake.txt): one "<name> <value>" line each.
found <- function() {
  x <- readLines(system.file("zigcmake.txt", package = "zigcmake"))
  setNames(sub("^[^ ]+ ", "", x), sub(" .*", "", x))
}
