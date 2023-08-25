
import 'package:flutter/material.dart';
import 'package:pull_to_refresh/pull_to_refresh.dart';

class RefreshIndicatorWidget extends StatefulWidget {
  final Widget child;
  final Future<void> Function() onRefresh;
  final ScrollController? scrollController;
  final RefreshController? refreshController;
  const RefreshIndicatorWidget({Key? key, required this.child, required this.onRefresh, this.scrollController, this.refreshController}) : super(key: key);

  @override
  State<RefreshIndicatorWidget> createState() => _RefreshIndicatorWidgetState();
}

class _RefreshIndicatorWidgetState extends State<RefreshIndicatorWidget> {
  @override
  Widget build(BuildContext context) {
    return NotificationListener(
      onNotification: (value) {
        return false;
      },
      child: SmartRefresher(
        enablePullUp: false,
        enablePullDown: true,
        physics: const ScrollPhysics(),
        enableTwoLevel: true,
        header: const WaterDropHeader(
          waterDropColor: Colors.transparent,

          idleIcon: SizedBox(width: 30, height: 30,child: CircularProgressIndicator()),
        ),
        controller: widget.refreshController!,
        scrollController: widget.scrollController,
        onRefresh: widget.onRefresh,
        child: widget.child,
      ),
    );
  }
}