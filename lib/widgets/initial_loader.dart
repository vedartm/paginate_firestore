import 'package:flutter/material.dart';

class InitialLoader extends StatelessWidget {
  const InitialLoader({super.key});

  @override
  Widget build(BuildContext context) {
    return const SingleChildScrollView(
        child: Center(child: CircularProgressIndicator(strokeWidth: 2)));
  }
}
