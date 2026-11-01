# SPDX-License-Identifier: MIT
#
# The shell command that patches an elm-test source tree so that elm-test
# puts its socket in os.tmpdir(), the directory TMPDIR names, instead of
# at /tmp/elm_test-<pid>.sock. Both elm-test packages of this flake run it
# in postPatch.
''
  substituteInPlace lib/RunTests.js \
    --replace-fail '`/tmp/elm_test-' '`''${require("os").tmpdir()}/elm_test-'
''
