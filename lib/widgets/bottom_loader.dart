import 'package:flutter/material.dart';

class BottomLoader extends StatelessWidget {
  final double? width;
  final double? height;
  final Color? indicatorColor;
  final double? strokeWidth;
  const BottomLoader({Key? key, this.width=16, this.height=16, this.indicatorColor=Colors.blue, this.strokeWidth=2.0}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.only(top: 16, bottom: 24),
        child: SizedBox(
          height: height,
          width: width,
          child: CircularProgressIndicator(
            strokeWidth: strokeWidth!,
            color: indicatorColor,
          ),
        ),
      ),
    );
  }
}
