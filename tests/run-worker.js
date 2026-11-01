// SPDX-License-Identifier: MIT
//
// Runs a compiled Elm worker that sends one string through its `output`
// port, and prints that string.
//
//   node run-worker.js COMPILED.js MODULE FLAGS
const [compiled, moduleName, flags] = process.argv.slice(2);
const { Elm } = require(compiled);
const program = moduleName.split(".").reduce((scope, part) => scope[part], Elm);
const app = program.init({ flags });
app.ports.output.subscribe((message) => {
  console.log(message);
});
