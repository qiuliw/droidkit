import 'package:droidkit/src/catalog/resolver.dart';
import 'package:droidkit/src/commands/droidkit_command.dart';
import 'package:droidkit/src/util.dart';
import 'package:mason_logger/mason_logger.dart';

/// `droidkit images`.
class ImagesCommand extends DroidkitCommand {
  /// Creates an [ImagesCommand].
  ImagesCommand(super.context) {
    argParser
      ..addOption('api', help: 'Only show images for this API level.')
      ..addOption(
        'tag',
        help: 'Only show images with this tag.',
        allowedHelp: systemImageTags,
      )
      ..addFlag(
        'all',
        negatable: false,
        help: 'Include previews, extension-level and 16 KB page-size images.',
      );
  }

  @override
  String get name => 'images';

  @override
  String get description =>
      'List emulator system images that run on this computer.';

  @override
  Future<int> run() async {
    maxArgs(0);
    final ctx = await context();
    final apiArg = argResults!['api'] as String?;
    final api = apiArg == null ? null : int.tryParse(apiArg);
    if (apiArg != null && api == null) {
      usageException('--api must be a number.');
    }
    final tag = argResults!['tag'] as String?;

    final catalog = await ctx.spinner(
      'Fetching system image catalogs',
      ctx.catalogs.systemImages,
    );
    final sdk = await ctx.sdk();
    final installed = {for (final i in sdk.installedPackages()) i.path};

    final images = PackageResolver(catalog, ctx.host).systemImages(
      tag: tag,
      api: api,
      includePreview: argResults!['all'] as bool,
    );
    if (images.isEmpty) {
      logger.info('No matching images for ${ctx.host.arch.systemImageAbi}.');
      return ExitCode.success.code;
    }
    logger.info(
      styleBold.wrap(
        'System images for ${ctx.host.arch.systemImageAbi} '
        '(✓ = installed):',
      ),
    );
    for (final image in images) {
      final mark = installed.contains(image.path) ? green.wrap('✓')! : ' ';
      logger.info(
        '$mark ${image.path.padRight(62)} '
        '${darkGray.wrap(formatBytes(image.sizeFor(ctx.host) ?? 0))}',
      );
    }
    logger.detail(
      'Create an emulator: droidkit avd create --api <N> --image <tag>',
    );
    return ExitCode.success.code;
  }
}
