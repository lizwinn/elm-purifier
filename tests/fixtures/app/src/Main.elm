port module Main exposing (main)

import Greet


port output : String -> Cmd msg


main : Program String () ()
main =
    Platform.worker
        { init = \name -> ( (), output (Greet.greeting name) )
        , update = \_ model -> ( model, Cmd.none )
        , subscriptions = \_ -> Sub.none
        }
