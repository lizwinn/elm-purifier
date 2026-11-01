module GreetingTest exposing (suite)

import Expect
import Greeting
import Json.Encode as Encode
import Test exposing (Test, describe, test)


suite : Test
suite =
    describe "Greeting"
        [ test "greeting" <|
            \_ -> Expect.equal "Hello, Nix!" (Greeting.greeting "Nix")
        , test "encode" <|
            \_ ->
                Expect.equal "{\"greeting\":\"Hello, Nix!\"}"
                    (Encode.encode 0 (Greeting.encode "Nix"))
        ]
