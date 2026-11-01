module Greeting exposing (greeting, encode)

{-| Greetings, for elm-purifier's package fixture.

@docs greeting, encode

-}

import Json.Encode as Encode


{-| A greeting for a name.
-}
greeting : String -> String
greeting name =
    "Hello, " ++ name ++ "!"


{-| A greeting for a name, as JSON.
-}
encode : String -> Encode.Value
encode name =
    Encode.object [ ( "greeting", Encode.string (greeting name) ) ]
