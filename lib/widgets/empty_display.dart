import 'package:flutter/material.dart';
import 'package:paginate_firestore/utils/internationalization.dart';

class EmptyDisplay extends StatelessWidget {
  const EmptyDisplay({Key? key, this.internationalizationHelper})
      : super(key: key);
  final InternationalizationHelper? internationalizationHelper;

  @override
  Widget build(BuildContext context) {
    String noDocumentsFound = internationalizationHelper != null
        ? internationalizationHelper!.noDocumentsFound
        : InternationalizationHelper.noDocumentsFoundEnglish;
    return Center(child: Text(noDocumentsFound));
  }
}
