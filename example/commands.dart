import "package:belt/io.dart";

main() async {
  print(await executeCommand(
    "sha256sum",
    stdin: "Hello"
  ));
}
