import "package:belt/io.dart";

import "dart:io";

main() async {
  var result = await executeCommand(
    "bash",
    inherit: true,
    inheritStdin: true,
    inheritSignals: true,
    tty: true,
    binary: true
  );

  exit(result.exitCode);
}
