import 'package:flutter/material.dart';

class PageTitle extends StatelessWidget {
  const PageTitle(this.text, {super.key});
  final String text;
  @override
  Widget build(BuildContext context) => Text(
    text,
    maxLines: 2,
    softWrap: true,
    style: Theme.of(context).textTheme.titleLarge?.copyWith(
      fontSize:
          MediaQuery.sizeOf(context).width >
                  MediaQuery.sizeOf(context).height ||
              MediaQuery.textScalerOf(context).scale(1) > 1.3
          ? 24
          : 28,
    ),
  );
}
