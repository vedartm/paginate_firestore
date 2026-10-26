import 'package:flutter/material.dart';

class EmptyDisplay extends StatelessWidget {
  const EmptyDisplay({super.key});

  @override
  Widget build(BuildContext context) {
    return const Center(child: Text('No documents found'));
  }
}
