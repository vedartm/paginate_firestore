import 'package:flutter/material.dart';
import 'package:paginate_firestore/utils/internationalization.dart';

class ErrorDisplay extends StatelessWidget {
  const ErrorDisplay(
      {Key? key, required this.exception, this.internationalizationHelper})
      : super(key: key);

  final Exception exception;
  final InternationalizationHelper? internationalizationHelper;

  @override
  Widget build(BuildContext context) {
    String errorMessage = internationalizationHelper != null
        ? internationalizationHelper!.errorOccurred
        : InternationalizationHelper.errorOccurredEnglish;
    return Center(child: Text('$errorMessage: $exception'));
  }
}
