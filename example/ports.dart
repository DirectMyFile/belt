import "package:belt/io.dart";

main() async {
  for (int port in const <int>[
    22,
    80,
    8080
  ]) {
    await checkPort(port);
    await checkPort(port, ipv6: true);
  }
}

checkPort(int port, {bool ipv6: false}) async {
  var result = await isPortOpen(port, ipv6: ipv6);

  if (result) {
    print("Port ${port}${ipv6 ? ' (IPv6)' : ''} is open.");
  } else {
    print("Port ${port}${ipv6 ? ' (IPv6)' : ''} is not open.");
  }
}
