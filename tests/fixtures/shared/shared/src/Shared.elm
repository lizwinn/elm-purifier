module Shared exposing (greeting)


greeting : String -> String
greeting name =
    "Hello from the shared directory, " ++ name ++ "!"
