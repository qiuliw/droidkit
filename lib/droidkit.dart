/// Set up the Android SDK, a JDK and emulators for Flutter without Android
/// Studio.
///
/// This library exposes the command runner so droidkit can be embedded in
/// other tools; most users should install the CLI instead:
///
/// ```sh
/// dart pub global activate droidkit
/// droidkit setup
/// ```
library;

export 'src/command_runner.dart' show DroidkitCommandRunner;
export 'src/version.dart' show packageVersion;
