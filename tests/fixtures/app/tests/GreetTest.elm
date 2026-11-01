module GreetTest exposing (suite)

import Expect
import Greet
import Test exposing (Test, test)


suite : Test
suite =
    test "greeting" <|
        \_ -> Expect.equal "Hello, Nix!" (Greet.greeting "Nix")
