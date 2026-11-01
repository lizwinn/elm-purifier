port module Main exposing (main)

import Json.Encode as Encode
import Shared


port output : String -> Cmd msg


main : Program String () ()
main =
    Platform.worker
        { init = \name -> ( (), output (Encode.encode 0 (Encode.string (Shared.greeting name))) )
        , update = \_ model -> ( model, Cmd.none )
        , subscriptions = \_ -> Sub.none
        }
