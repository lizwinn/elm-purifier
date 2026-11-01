port module Main exposing (main)

import Json.Encode as Encode


port output : String -> Cmd msg


main : Program String () ()
main =
    Platform.worker
        { init = \name -> ( (), output (Encode.encode 0 (Encode.string ("Hello from an external lockfile, " ++ name ++ "!"))) )
        , update = \_ model -> ( model, Cmd.none )
        , subscriptions = \_ -> Sub.none
        }
