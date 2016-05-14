import "package:belt/qts.dart";

main(List<String> args) async {
  String sec = args[0];
  String arg = args[1];

  if (sec == "client") {
    var client = new QuickTerminalClient(arg);
    await client.connect();
  } else if (sec == "server") {
    var port = int.parse(arg);
    var exe = args[2];
    var argz = args.skip(3).toList();
    var server = new QuickTerminalServer(exe, argz);
    await server.startInsecureServer(port: port);
  }
}
