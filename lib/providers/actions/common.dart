part of '../action.dart';

@Riverpod(keepAlive: true)
class CommonAction extends _$CommonAction {
  CoreController get _core => ref.read(coreHandlerProvider);
  bool _isUpdatingTraffic = false;

  @override
  void build() {}

  void toggleRunning() {
    final running = !ref.read(isStartProvider);
    unawaited(
      globalState.safeRun(
        () => ref
            .read(setupActionProvider.notifier)
            .setRunning(
              running,
              initialize: running && !ref.read(initProvider),
            ),
      ),
    );
  }

  void updateSpeedStatistics() {
    ref
        .read(appSettingProvider.notifier)
        .update((state) => state.copyWith(showTrayTitle: !state.showTrayTitle));
  }

  void updateMonochromeTrayIcon() {
    ref
        .read(appSettingProvider.notifier)
        .update(
          (state) =>
              state.copyWith(monochromeTrayIcon: !state.monochromeTrayIcon),
        );
  }

  void updateMode() {
    ref.read(patchClashConfigProvider.notifier).update((state) {
      final index = Mode.values.indexWhere((item) => item == state.mode);
      if (index == -1) return state;
      final nextIndex = index + 1 > Mode.values.length - 1 ? 0 : index + 1;
      return state.copyWith(mode: Mode.values[nextIndex]);
    });
  }

  Future<void> updateTraffic() async {
    if (_isUpdatingTraffic) {
      return;
    }
    _isUpdatingTraffic = true;
    try {
      final onlyStatisticsProxy = ref.read(
        appSettingProvider.select((state) => state.onlyStatisticsProxy),
      );
      final [traffic, totalTraffic] = await Future.wait([
        _readTraffic(() => _core.getTraffic(onlyStatisticsProxy)),
        _readTraffic(() => _core.getTotalTraffic(onlyStatisticsProxy)),
      ]);
      if (traffic != null) {
        ref.read(trafficsProvider.notifier).addTraffic(traffic);
      }
      if (totalTraffic != null) {
        ref.read(totalTrafficProvider.notifier).value = totalTraffic;
      }
    } finally {
      _isUpdatingTraffic = false;
    }
  }

  Future<Traffic?> _readTraffic(Future<Traffic> Function() request) async {
    try {
      return await request();
    } catch (error) {
      commonPrint.log(
        'updateTraffic error: $error',
        logLevel: coreFailureLogLevel(error),
      );
      return null;
    }
  }

  Future<bool> autoCheckUpdate() async {
    if (!ref.read(appSettingProvider).autoCheckUpdate) return false;
    final Map<String, dynamic>? res;
    try {
      res = await request.checkForUpdate();
    } catch (error) {
      commonPrint.log(
        'checkForUpdate failed: ${compactError(error)}',
        logLevel: LogLevel.warning,
      );
      return false;
    }
    await checkUpdateResultHandle(data: res);
    return res != null;
  }

  TextSpan _releaseSpan(BuildContext context, String tagName, String? body) {
    final version = parseReleaseChangelog(body);
    return TextSpan(
      text: '$tagName \n',
      style: AppTextStyle.title2.of(context),
      children: version == null
          ? [
              TextSpan(text: '\n', style: AppTextStyle.subheadline.of(context)),
              for (final submit in parseReleaseBody(body))
                TextSpan(
                  text: '- $submit \n',
                  style: AppTextStyle.subheadline.of(context),
                ),
            ]
          : _changelogSpans(context, version),
    );
  }

  List<TextSpan> _changelogSpans(
    BuildContext context,
    ChangelogVersion version,
  ) {
    return [
      for (final group in version.visibleGroups) ...[
        TextSpan(
          text:
              '\n${changelogGroupTitle(currentAppLocalizations, group.type)}\n',
          style: AppTextStyle.subheadline
              .of(context, emphasized: true)
              .copyWith(
                color: group.type == ChangelogType.breaking
                    ? context.colorScheme.error
                    : context.colorScheme.primary,
              ),
        ),
        for (final entry in group.entries)
          TextSpan(
            text: '• ${entry.text}\n',
            style: AppTextStyle.subheadline.of(context),
          ),
      ],
    ];
  }

  String? _findApkUrl(Map<String, dynamic> data) {
    final rawAssets = data['assets'];
    if (rawAssets is List && rawAssets.isNotEmpty) {
      final apkAssets = rawAssets
          .whereType<Map>()
          .where((a) => (a['name']?.toString() ?? '').endsWith('.apk'))
          .toList();
      if (apkAssets.isNotEmpty) {
        final arm64 = apkAssets.firstWhereOrNull(
          (a) => (a['name']?.toString() ?? '').contains('arm64'),
        );
        final selected = arm64 ?? apkAssets.first;
        final url = selected['browser_download_url']?.toString();
        if (url != null && url.isNotEmpty) {
          return url;
        }
      }
    }
    final tagName = data['tag_name'] as String?;
    if (tagName != null && tagName.isNotEmpty) {
      final ver = tagName.startsWith('v') ? tagName.substring(1) : tagName;
      return 'https://github.com/$repository/releases/download/$tagName/FlClash-$ver-android-arm64-v8a.apk';
    }
    return null;
  }

  Future<void> _downloadAndInstallApk(String url) async {
    final tempPath = await appPath.tempDirPath;
    final apkPath = join(tempPath, 'update.apk');
    final file = File(apkPath);
    if (await file.exists()) {
      try {
        await file.delete();
      } catch (_) {}
    }

    final cancelToken = CancelToken();
    final progressNotifier = ValueNotifier<double>(0.0);
    final statusNotifier = ValueNotifier<String>('0%');
    final dialogReady = Completer<BuildContext>();

    unawaited(
      dialogs.showCommonDialog<void>(
        dismissible: false,
        child: PopScope(
          canPop: false,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop) {
              cancelToken.cancel();
              if (dialogReady.isCompleted) {
                dialogReady.future.then((ctx) {
                  if (ctx.mounted) Navigator.of(ctx).pop();
                });
              }
            }
          },
          child: Builder(
            builder: (ctx) {
              if (!dialogReady.isCompleted) {
                dialogReady.complete(ctx);
              }
              return CommonDialog(
                title: currentAppLocalizations.download,
                actions: [
                  TextButton(
                    onPressed: () {
                      cancelToken.cancel();
                      Navigator.of(ctx).pop();
                    },
                    child: Text(currentAppLocalizations.cancel),
                  ),
                ],
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ValueListenableBuilder<double>(
                      valueListenable: progressNotifier,
                      builder: (context, progress, _) {
                        return LinearProgressIndicator(
                          value: progress > 0 ? progress : null,
                        );
                      },
                    ),
                    const SizedBox(height: 12),
                    ValueListenableBuilder<String>(
                      valueListenable: statusNotifier,
                      builder: (context, text, _) {
                        return Text(
                          text,
                          style: AppTextStyle.subheadline.of(context),
                        );
                      },
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );

    var success = false;
    Object? downloadError;
    try {
      await request.dio.download(
        url,
        apkPath,
        cancelToken: cancelToken,
        onReceiveProgress: (count, total) {
          if (total > 0) {
            final progress = (count / total).clamp(0.0, 1.0);
            progressNotifier.value = progress;
            final currentMb = (count / (1024 * 1024)).toStringAsFixed(1);
            final totalMb = (total / (1024 * 1024)).toStringAsFixed(1);
            final percent = (progress * 100).toInt();
            statusNotifier.value = '$percent% ($currentMb MB / $totalMb MB)';
          }
        },
      );
      success = true;
    } catch (e) {
      downloadError = e;
    }

    try {
      final ctx = await dialogReady.future.timeout(const Duration(seconds: 2));
      if (ctx.mounted) {
        Navigator.of(ctx).pop();
      }
    } catch (_) {}

    if (cancelToken.isCancelled) {
      if (await file.exists()) {
        try {
          await file.delete();
        } catch (_) {}
      }
      return;
    }

    if (!success) {
      if (await file.exists()) {
        try {
          await file.delete();
        } catch (_) {}
      }
      final retry = await dialogs.showMessage(
        title: currentAppLocalizations.tip,
        message: TextSpan(
          text:
              '${currentAppLocalizations.networkRequestFailed(compactError(downloadError))}\n\n'
              '${currentAppLocalizations.goDownload}?',
        ),
        confirmText: system.isAndroid
            ? currentAppLocalizations.update
            : currentAppLocalizations.goDownload,
      );
      if (retry == true) {
        unawaited(
          launchUrl(
            Uri.parse('https://github.com/$repository/releases/latest'),
          ),
        );
      }
      return;
    }

    final installed = await app?.installApk(apkPath) ?? false;
    if (!installed) {
      final retry = await dialogs.showMessage(
        title: currentAppLocalizations.tip,
        message: TextSpan(text: currentAppLocalizations.goDownload),
        confirmText: system.isAndroid
            ? currentAppLocalizations.update
            : currentAppLocalizations.goDownload,
      );
      if (retry == true) {
        unawaited(
          launchUrl(
            Uri.parse('https://github.com/$repository/releases/latest'),
          ),
        );
      }
    }
  }

  Future<void> checkUpdateResultHandle({
    Map<String, dynamic>? data,
    bool isUser = false,
  }) async {
    if (data != null) {
      final context = globalState.navigatorKey.currentContext!;
      final res = await dialogs.showMessage(
        title: currentAppLocalizations.discoverNewVersion,
        message: _releaseSpan(
          context,
          data['tag_name'] as String,
          data['body'] as String?,
        ),
        confirmText: system.isAndroid
            ? currentAppLocalizations.update
            : currentAppLocalizations.goDownload,
        cancelText: isUser ? null : currentAppLocalizations.noLongerRemind,
      );
      if (res == true) {
        if (system.isAndroid) {
          final apkUrl = _findApkUrl(data);
          if (apkUrl != null) {
            await _downloadAndInstallApk(apkUrl);
            return;
          }
        }
        unawaited(
          launchUrl(
            Uri.parse('https://github.com/$repository/releases/latest'),
          ),
        );
      } else if (!isUser && res == false) {
        ref
            .read(appSettingProvider.notifier)
            .update((state) => state.copyWith(autoCheckUpdate: false));
      }
    } else if (isUser) {
      unawaited(
        dialogs.showAlert(
          title: currentAppLocalizations.checkUpdate,
          message: TextSpan(text: currentAppLocalizations.checkUpdateError),
        ),
      );
    }
  }
}
