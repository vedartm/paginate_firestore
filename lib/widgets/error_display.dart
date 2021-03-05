import 'package:flutter/material.dart';

class ErrorDisplay extends StatelessWidget {
  const ErrorDisplay({Key? key, required this.exception}) : super(key: key);

  final Exception exception;

  @override
  Widget build(BuildContext context) {
    return Center(child: Text('Error occured: $exception'));
  }
}
