import 'package:flutter/material.dart';

/// Displays a user avatar with an optional edit badge overlay.
class AvatarPreview extends StatelessWidget {
  final String avatarUrl;
  final double radius;
  final bool showEditIndicator;
  final bool? connectionStatus;
  const AvatarPreview({
    super.key,
    required this.avatarUrl,
    this.showEditIndicator = false,
    this.radius = 50,
    this.connectionStatus,
  });

  @override
  Widget build(BuildContext context) {
    final hasAvatar = avatarUrl.isNotEmpty;
    final status = connectionStatus;
    final indicatorColor = status == null
        ? null
        : (status ? Colors.green : Colors.red);
    final ringDiameter = radius * 2 + 8; // 4px gap each side
    return SizedBox(
      width: ringDiameter,
      height: ringDiameter,
      child: Stack(
        alignment: Alignment.center,
        children: [
          if (indicatorColor != null)
            IgnorePointer(
              child: Container(
                width: ringDiameter,
                height: ringDiameter,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: indicatorColor, width: 4),
                ),
              ),
            ),
          CircleAvatar(
            radius: radius - (indicatorColor != null ? 4 : 0),
            backgroundColor: ColorScheme.of(context).surfaceContainerHighest,
            backgroundImage: hasAvatar ? NetworkImage(avatarUrl) : null,
            child: hasAvatar ? null : Icon(Icons.person, size: radius),
          ),
          if (showEditIndicator)
            Positioned(
              bottom: 0,
              right: 0,
              child: PhysicalModel(
                color: Colors.transparent,
                elevation: 4,
                shadowColor: ColorScheme.of(context).shadow,
                shape: BoxShape.circle,
                child: CircleAvatar(
                  radius: radius / 2.5,
                  backgroundColor: ColorScheme.of(context).primaryFixed,
                  child: Icon(
                    Icons.edit,
                    size: radius / 2.5,
                    color: ColorScheme.of(context).onPrimaryFixed,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
