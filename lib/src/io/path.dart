part of belt.io;

Map<String, String> _executableCache = {};

Future<String> findExecutable(String name, {bool force: false}) async {
  if (_executableCache.containsKey(name) && !force) {
    var file = new File(_executableCache[name]);
    if (await file.exists()) {
      return file.path;
    }
  }

  if (const [
    "dart",
    "pub"
  ].contains(name)) {
    try {
      var exeFile = new File(Platform.resolvedExecutable);
      var binDir = exeFile.parent;
      var file = new File(pathlib.join(binDir.path, name));

      if (await file.exists()) {
        return _executableCache[name] = file.absolute.path;
      }
    } catch (e) {}
  }

  var paths = Platform.environment["PATH"].split(
    Platform.isWindows ? ";" : ":");
  var tryFiles = [name];

  if (Platform.isWindows) {
    tryFiles.addAll(["${name}.exe", "${name}.bat"]);
  }

  for (var p in paths) {
    if (p.startsWith('"') && p.endsWith('"')) {
      p = p.substring(1, p.length - 1);
    }

    if (Platform.environment.containsKey("HOME")) {
      p = p.replaceAll("~/", Platform.environment["HOME"] + "/");
    }

    var dir = new Directory(pathlib.normalize(p));

    if (!(await dir.exists())) {
      continue;
    }

    for (var t in tryFiles) {
      var file = new File("${dir.path}/${t}");

      if (await file.exists()) {
        _executableCache[name] = file.path;
        return file.path;
      }
    }
  }

  return null;
}

Future<bool> isCommandInstalled(String name, {bool force: false}) async {
  return (await findExecutable(name, force: force)) != null;
}
