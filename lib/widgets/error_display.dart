import 'package:flutter/material.dart';

class ErrorDisplay extends StatelessWidget {
  const ErrorDisplay({super.key, required this.exception});

  final Exception exception;

  @override
  Widget build(BuildContext context) {
    return Center(child: Text('Error occured: $exception'));
  }
}
