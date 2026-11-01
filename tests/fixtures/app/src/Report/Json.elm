port module Report.Json exposing (main)

import Greet
import Json.Encode as Encode


port output : String -> Cmd msg


main : Program String () ()
main =
    Platform.worker
        { init =
            \name ->
                ( ()
                , output
                    (Encode.encode 0
                        (Encode.object [ ( "greeting", Encode.string (Greet.greeting name) ) ])
                    )
                )
        , update = \_ model -> ( model, Cmd.none )
        , subscriptions = \_ -> Sub.none
        }
