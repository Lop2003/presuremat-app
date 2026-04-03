import 'package:flutter/material.dart';

class ModernCard extends StatelessWidget {
  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry padding;

  const ModernCard({super.key, required this.child, this.onTap, this.padding = const EdgeInsets.all(16)});

  @override
  Widget build(BuildContext context) {
    final card = Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: padding,
          child: child,
        ),
      ),
    );
    return card;
  }
}


