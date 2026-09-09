import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:tsdm_client/exceptions/exceptions.dart';
import 'package:tsdm_client/extensions/fp.dart';
import 'package:tsdm_client/features/authentication/repository/authentication_repository.dart';
import 'package:tsdm_client/i18n/strings.g.dart';
import 'package:tsdm_client/utils/logger.dart';
import 'package:tsdm_client/widgets/fallback_picture.dart';
import 'package:tsdm_client/widgets/indicator.dart';

/// Captcha image size is 320x150.
const _captchaImageWidth = 320.0;
const _captchaImageHeight = 150.0;

const _renderHeight = 52.0;

const double _indicatorBoxWidth = (_renderHeight / _captchaImageHeight) * _captchaImageWidth;

/// The captcha image used in login form.
class CaptchaImage extends StatefulWidget {
  /// Constructor.
  const CaptchaImage({required this.imageUrl, required this.onRefresh, super.key});

  /// Captcha image source from the current Discuz challenge.
  final String imageUrl;

  /// Request a fresh complete login challenge.
  final VoidCallback onRefresh;

  @override
  State<CaptchaImage> createState() => _CaptchaImageState();
}

class _CaptchaImageState extends State<CaptchaImage> with LoggerMixin {
  /// Need this variable to mark whether the future [f] is completed or not.
  /// Because when refreshing state triggered by user interaction, it's weired
  /// that the [FutureBuilder] below has the previous data and does not show
  /// [CircularProgressIndicator] as planned.
  bool futureComplete = false;
  Future<SyncEither<List<int>>>? f;

  void reload() {
    debug('fetching login captcha');
    f = context.read<AuthenticationRepository>().fetchCaptchaImage(widget.imageUrl).run().whenComplete(() {
      futureComplete = true;
    });

    setState(() {
      futureComplete = false;
    });
    debug('refresh login captcha');
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => reload());
  }

  @override
  void didUpdateWidget(CaptchaImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.imageUrl != widget.imageUrl) {
      reload();
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onRefresh,
      child: FutureBuilder(
        future: f,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            // Impossible.
            final message = t.loginPage.failedToGetCaptcha(err: snapshot.error!);
            debug(message);
            return Text(message);
          }

          if (snapshot.hasData && futureComplete) {
            final either = snapshot.data!;
            if (either.isLeft()) {
              handle(either.unwrapErr());
              return const FallbackPicture();
            }

            final bytes = Uint8List.fromList(snapshot.data!.unwrap());
            debug('fetch login captcha finished, ${f.hashCode}');
            // 130 x 60 -> 110.9 -> 52
            return Image.memory(bytes, height: _renderHeight);
          }
          return const SizedBox(width: _indicatorBoxWidth, child: CenteredCircularIndicator());
        },
      ),
    );
  }
}
