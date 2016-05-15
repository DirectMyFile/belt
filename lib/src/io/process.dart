part of belt.io;

/// A callback handler for [BetterProcessResult] objects.
typedef ProcessResultHandler(BetterProcessResult result);

/// A callback handler for [Process] objects.
typedef ProcessHandler(Process process);

/// A callback handler for process output data.
typedef ProcessOutputHandler(data);

/// A callback handler to retrieve the [ProcessAdapterReferences] adapter.
typedef ProcessAdapterHandler(ProcessAdapterReferences adapter);

/// A callback handler for process logging.
typedef ProcessLogHandler(String message);

Stdin get _stdin => stdin;

/// An improved process result with combined stdout + stderr output.
class BetterProcessResult extends ProcessResult {
  /// The full process output.
  final output;

  BetterProcessResult(int pid, int exitCode, stdout, stderr, this.output)
    : super(pid, exitCode, stdout, stderr);

  @override
  String toString() => output.toString().trim();
}

/// A class to pass in flags in the references for
/// the [executeCommand] method.
class ProcessAdapterFlags {
  /// Should we inherit stdio?
  bool inherit = false;

  /// Output log file.
  File logFile;

  /// Logging callback handler.
  ProcessLogHandler logHandler;
}

/// Process references.
class ProcessAdapterReferences {
  /// The process result.
  BetterProcessResult result;

  /// Process object.
  Process process;

  /// Process flags.
  ProcessAdapterFlags flags = new ProcessAdapterFlags();

  /// Handle when the process result is ready.
  Future<BetterProcessResult> get onResultReady {
    if (result != null) {
      return new Future.value(result);
    } else {
      var c = new Completer<BetterProcessResult>();
      _onResultReady.add(c.complete);
      return c.future;
    }
  }

  /// Handle when the process is ready.
  Future<Process> get onProcessReady {
    if (process != null) {
      return new Future.value(process);
    } else {
      var c = new Completer<Process>();
      _onProcessReady.add(c.complete);
      return c.future;
    }
  }

  List<ProcessResultHandler> _onResultReady = <ProcessResultHandler>[];
  List<ProcessHandler> _onProcessReady = <ProcessHandler>[];

  /// Pushes the process into the reference.
  void pushProcess(Process process) {
    this.process = process;
    while (_onProcessReady.isNotEmpty) {
      _onProcessReady.removeAt(0)(process);
    }
  }

  /// Pushes the result into the reference.
  void pushResult(BetterProcessResult result) {
    this.result = result;
    while (_onResultReady.isNotEmpty) {
      _onResultReady.removeAt(0)(result);
    }
  }
}

/// Execute a Command.
///
/// [executable] is the name or path to the executable to run.<br/>
/// [args] is an optional list of arguments for the executable.<br/>
/// [workingDirectory] is a path to the directory to execute the command in.<br/>
/// [includeParentEnvironment] specifies whether the process should inherit the current environment.<br/>
/// [runInShell] specified whether the process should run in a command line shell.<br/>
/// [stdin] is an instance of any of the following:
/// - [String]
/// - [List<int>]
/// - [Stream<String>]
/// - [Stream<List<int>>]
/// - [File]
/// that will be passed as the input of the command.<br/>
/// [handler] specifies a callback for the [Process] object.<br/>
/// [stdoutHandler] specifies a callback for stdout data.<br/>
/// [stderrHandler] specifies a callback for stderr data.<br/>
/// [outputHandler] specifies a callback for any output data.<br/>
/// [outputFile] specifies a file to write log data to.<br/>
/// [inherit] specifies whether to write data to the stdout/stderr of the current process.<br/>
/// [writeToBuffer] specifies whether to write output to buffers for the process result.<br/>
/// [binary] specifies whether to treat the process output like binary data.<br/>
/// [resultHandler] specifies a callback for the [BetterProcessResult] instance.<br/>
/// [inheritStdin] specifies whether the current process stdin should be piped to the process.<br/>
/// [inheritSignals] specifies whether the current process should proxy signals to the process.<br/>
/// [logHandler] specifies a callback for any logging output.<br/>
/// [sudo] specifies whether to run the command as root if possible or not.<br/>
/// [tty] specifies whether to attempt to emulate a TTY or not.<br/>
/// [refs] specifies the [ProcessAdapterReferences] instance.<br/>
/// [refs] can also be specified using the zone value `belt.io.process.ref`.<br/>
/// [lineBased] specifies whether to process output based on newlines.<br/>
Future<BetterProcessResult> executeCommand(
  String executable,
  {
    List<String> args: const [],
    String workingDirectory,
    Map<String, dynamic> environment,
    bool includeParentEnvironment: true,
    bool runInShell: false,
    stdin,
    ProcessHandler handler,
    ProcessOutputHandler stdoutHandler,
    ProcessOutputHandler stderrHandler,
    ProcessOutputHandler outputHandler,
    File outputFile,
    bool inherit: false,
    bool inheritSignals: false,
    bool inheritStdin: false,
    bool writeToBuffer: true,
    bool binary: false,
    ProcessResultHandler resultHandler,
    ProcessLogHandler logHandler,
    bool sudo: false,
    bool tty: false,
    ProcessAdapterReferences refs,
    bool lineBased: true
  }) async {
  if (args == null) {
    args = <String>[];
  }

  {
    if (environment == null) {
      environment = <String, dynamic>{};
    }

    var env = <String, dynamic>{};

    for (String key in environment.keys) {
      env[key] = environment[key].toString();
    }

    environment = env;
  }

  args = args.map((arg) => arg.toString()).toList();

  if (sudo && BeltPlatform.isUnix && await isCommandInstalled("sudo")) {
    args.insert(0, executable);
    executable = await findExecutable("sudo");
  }

  if (tty && BeltPlatform.isUnix && await isCommandInstalled("script")) {
    var realArguments = args;

    List<String> scriptArgs;

    if (Platform.isMacOS) {
      scriptArgs = ["-q", "/dev/null", executable];
      scriptArgs.addAll(realArguments);
    } else {
      var command = executable;

      if (realArguments.isNotEmpty) {
        command += " ";
        command += escapeCommandArguments(realArguments);
      }

      scriptArgs = <String>["-qfc", command, "/dev/null"];
    }

    executable = await findExecutable("script");
    args = scriptArgs;
  }

  ProcessAdapterReferences refs = Zone.current["belt.io.process.ref"];

  if (refs != null) {
    outputFile = outputFile != null ? outputFile : refs.flags.logFile;
    logHandler = logHandler != null ? logHandler : refs.flags.logHandler;
  }

  IOSink raf;

  if (outputFile != null) {
    if (!(await outputFile.exists())) {
      await outputFile.create(recursive: true);
    }

    raf = await outputFile.openWrite(mode: FileMode.APPEND);
  }

  if (inheritStdin) {
    _p(String k) {
      if (Platform.environment[k] is String) {
        environment[k] = Platform.environment[k];
      }
    }

    _p("TERM");
    _p("LINES");
    _p("COLUMNS");

    _stdin.lineMode = false;
    _stdin.echoMode = false;
  }

  try {
    Process process = await Process.start(
      executable,
      args,
      workingDirectory: workingDirectory,
      environment: environment,
      includeParentEnvironment: includeParentEnvironment,
      runInShell: runInShell
    );

    var signalSubs = <StreamSubscription>[];

    if (inheritSignals) {
      proxy(ProcessSignal signal) {
        signalSubs.add(signal.watch().listen((ProcessSignal signal) {
          if (process != null) {
            process.kill(signal);
          }
        }));
      }

      proxy(ProcessSignal.SIGINT);
      proxy(ProcessSignal.SIGHUP);
      proxy(ProcessSignal.SIGTERM);
      proxy(ProcessSignal.SIGUSR1);
      proxy(ProcessSignal.SIGUSR2);
      proxy(ProcessSignal.SIGWINCH);
    }

    var id = process.pid.toString();

    if (refs != null) {
      refs.pushProcess(process);
      inherit = inherit || refs.flags.inherit;
    }

    if (raf != null) {
      await raf.writeln(
        "[${_currentTimestamp}][${id}] == Executing ${executable}"
          " with arguments ${args} (pid: ${process.pid}) =="
      );
    }

    if (logHandler != null) {
      logHandler(
        "[${_currentTimestamp}][${id}] == Executing ${executable}"
          " with arguments ${args} (pid: ${process.pid}) =="
      );
    }

    var buff = new StringBuffer();
    var ob = new StringBuffer();
    var eb = new StringBuffer();

    var obytes = <int>[];
    var ebytes = <int>[];
    var sbytes = <int>[];

    if (!binary) {
      var stdoutDecoded = process.stdout
        .transform(const Utf8Decoder(allowMalformed: true));

      if (lineBased) {
        stdoutDecoded = stdoutDecoded.transform(const LineSplitter());
      }

      stdoutDecoded.listen((str) async {
        if (writeToBuffer) {
          ob.writeln(str);
          buff.writeln(str);
        }

        if (stdoutHandler != null) {
          stdoutHandler(str);
        }

        if (outputHandler != null) {
          outputHandler(str);
        }

        if (inherit) {
          if (lineBased) {
            stdout.writeln(str);
          } else {
            stdout.write(str);
          }
        }

        if (raf != null) {
          await raf.writeln("[${_currentTimestamp}][${id}] ${str}");
        }

        if (logHandler != null) {
          logHandler("[${_currentTimestamp}][${id}] ${str}");
        }
      });

      var stderrDecoded = process.stderr
        .transform(const Utf8Decoder(allowMalformed: true));

      if (lineBased) {
        stderrDecoded = stderrDecoded.transform(const LineSplitter());
      }

      stderrDecoded.listen((str) async {
        if (writeToBuffer) {
          eb.writeln(str);
          buff.writeln(str);
        }

        if (stderrHandler != null) {
          stderrHandler(str);
        }

        if (outputHandler != null) {
          outputHandler(str);
        }

        if (inherit) {
          if (lineBased) {
            stderr.writeln(str);
          } else {
            stderr.write(str);
          }
        }

        if (raf != null) {
          await raf.writeln("[${_currentTimestamp}][${id}] ${str}");
        }

        if (logHandler != null) {
          logHandler("[${_currentTimestamp}][${id}] ${str}");
        }
      });
    } else {
      process.stdout.listen((bytes) {
        if (writeToBuffer) {
          obytes.addAll(bytes);
          sbytes.addAll(bytes);
        }

        if (stdoutHandler != null) {
          stdoutHandler(bytes);
        }

        if (outputHandler != null) {
          outputHandler(bytes);
        }

        if (inherit) {
          stdout.add(bytes);
        }
      });

      process.stderr.listen((bytes) {
        if (writeToBuffer) {
          obytes.addAll(bytes);
          ebytes.addAll(bytes);
        }

        if (stderrHandler != null) {
          stderrHandler(bytes);
        }

        if (outputHandler != null) {
          outputHandler(bytes);
        }

        if (inherit) {
          stderr.add(bytes);
        }
      });
    }

    if (handler != null) {
      handler(process);
    }

    if (stdin != null) {
      if (stdin is File) {
        stdin = stdin.openRead();
      }

      if (stdin is Stream) {
        stdin.listen(process.stdin.add, onDone: process.stdin.close);
      } else if (stdin is List) {
        process.stdin.add(stdin);
      } else {
        process.stdin.write(stdin);
        await process.stdin.close();
      }
    } else if (inheritStdin) {
      _stdin.listen(process.stdin.add, onDone: process.stdin.close);
    }

    var code = await process.exitCode;
    await new Future.delayed(const Duration(milliseconds: 1));
    var pid = process.pid;

    if (raf != null) {
      await raf.writeln(
        "[${_currentTimestamp}][${id}] == Exited with status ${code} =="
      );
      await raf.flush();
      await raf.close();
    }

    if (logHandler != null) {
      logHandler(
        "[${_currentTimestamp}][${id}] == Exited with status ${code} =="
      );
    }

    for (StreamSubscription sub in signalSubs) {
      sub.cancel();
    }

    signalSubs.clear();

    var result = new BetterProcessResult(
      pid,
      code,
      binary ? sbytes : ob.toString(),
      binary ? ebytes : eb.toString(),
      binary ? obytes : buff.toString()
    );

    if (resultHandler != null) {
      resultHandler(result);
    }

    if (refs != null) {
      refs.pushResult(result);
    }

    return result;
  } finally {
    if (raf != null) {
      await raf.flush();
      await raf.close();
    }
  }
}

String get _currentTimestamp => new DateTime.now().toString();
