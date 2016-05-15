part of belt.io;

/// Platform Utilities.
class BeltPlatform {
  /// Is this a Unix platform?
  static bool isUnix = !Platform.isWindows;
}

/// Checks if the given [port] is open when bound to [host].
/// If [ipv6] is true, checks for IPv6.
/// If [host] is not specified, all host binds are checked.
Future<bool> isPortOpen(int port, {host, bool ipv6: false}) async {
  String realHost;

  if (host == null) {
    if (ipv6) {
      host = InternetAddress.ANY_IP_V6;
    } else {
      host = InternetAddress.ANY_IP_V4;
    }
  }

  if (host is String) {
    realHost = host.trim();
  } else if (host is InternetAddress) {
    realHost = host.address;

    if (host.type == InternetAddressType.IP_V6) {
      ipv6 = true;
    }
  }

  if (realHost.startsWith("[") || realHost.contains("::")) {
    ipv6 = true;
  }

  if (ipv6) {
    if (!realHost.startsWith("[")) {
      realHost = "[${realHost}";
    }

    if (!realHost.endsWith("]")) {
      realHost = "${realHost}]";
    }
  }

  try {
    if (BeltPlatform.isUnix &&
      await isCommandInstalled("lsof")) {
      var arg = ipv6 ?
        "-i6TCP@${realHost}:${port}" :
        "-i4TCP@${realHost}:${port}";

      var result = await executeCommand("lsof", args: <String>[
        "-n",
        arg
      ]);

      if (result.exitCode == 0 && result.stdout.contains("LISTEN")) {
        return false;
      }
    }

    ServerSocket server = await ServerSocket.bind(host, port);
    await server.close();
    return true;
  } catch (e) {
    return false;
  }
}

/// Turn a list of command line [arguments] into an escaped command string.
String escapeCommandArguments(List<String> arguments) {
  return arguments.map((arg) {
    return "'" + arg.replaceAll("'", "\\'") + "'";
  }).join(" ");
}
