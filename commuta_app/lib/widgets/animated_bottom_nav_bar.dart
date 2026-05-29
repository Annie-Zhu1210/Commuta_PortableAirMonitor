import 'package:flutter/material.dart';
import 'dart:math';

class AnimatedBottomNavBar extends StatefulWidget {
  final int currentIndex;
  final Function(int) onTap;
  final Color backgroundColour;
  final Color selectedItemColour;
  final Color unselectedItemColour;
  final List<BottomNavigationBarItem> items;

  const AnimatedBottomNavBar({
    super.key,
    required this.currentIndex,
    required this.onTap,
    required this.backgroundColour,
    required this.selectedItemColour,
    required this.unselectedItemColour,
    required this.items,
  });

  @override
  State<AnimatedBottomNavBar> createState() => _AnimatedBottomNavBarState();
}

class _AnimatedBottomNavBarState extends State<AnimatedBottomNavBar>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _animation;
  int _previousIndex = 0;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _animation = CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeInOutCubic,
    );
    _animationController.forward();
  }

  @override
  void didUpdateWidget(AnimatedBottomNavBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.currentIndex != widget.currentIndex) {
      _previousIndex = oldWidget.currentIndex;
      _animationController.forward(from: 0.0);
    }
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    
    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        return CustomPaint(
          size: Size(screenWidth, 95), // Total height including bump
          painter: WavyBottomBarPainter(
            color: widget.backgroundColour,
            currentIndex: widget.currentIndex,
            previousIndex: _previousIndex,
            animationValue: _animation.value,
            itemCount: widget.items.length,
          ),
          child: SafeArea(
            child: SizedBox(
              height: 70,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: List.generate(
                  widget.items.length,
                  (index) => _buildNavItem(index),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildNavItem(int index) {
    final isSelected = widget.currentIndex == index;
    final item = widget.items[index];

    return Expanded(
      child: InkWell(
        onTap: () => widget.onTap(index),
        splashColor: Colors.transparent,
        highlightColor: Colors.transparent,
        child: AnimatedBuilder(
          animation: _animation,
          builder: (context, child) {
            double scale = 1.0;
            double yOffset = 0.0;
            
            if (isSelected) {
              scale = 1.0 + (0.15 * _animation.value);
              yOffset = -5 * _animation.value;
            } else if (_previousIndex == index) {
              scale = 1.15 - (0.15 * _animation.value);
              yOffset = -5 + (5 * _animation.value);
            }

            return Transform.translate(
              offset: Offset(0, yOffset),
              child: Transform.scale(
                scale: scale,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      item.icon is Icon ? (item.icon as Icon).icon : Icons.circle,
                      color: isSelected
                          ? widget.selectedItemColour
                          : widget.unselectedItemColour,
                      size: 24,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      item.label ?? '',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                        color: isSelected
                            ? widget.selectedItemColour
                            : widget.unselectedItemColour,
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class WavyBottomBarPainter extends CustomPainter {
  final Color color;
  final int currentIndex;
  final int previousIndex;
  final double animationValue;
  final int itemCount;

  WavyBottomBarPainter({
    required this.color,
    required this.currentIndex,
    required this.previousIndex,
    required this.animationValue,
    required this.itemCount,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;

    final path = Path();
    
    final itemWidth = size.width / itemCount;
    final bumpHeight = 25.0; // How much the semicircle extends upward
    
    // Calculate animated center position of the bump
    final targetCenter = (currentIndex + 0.5) * itemWidth;
    final startCenter = (previousIndex + 0.5) * itemWidth;
    final currentCenter = startCenter + (targetCenter - startCenter) * animationValue;
    
    final radius = itemWidth / 2; // Diameter = itemWidth (x/4 of screen)
    
    // Start from top-left corner
    path.moveTo(0, bumpHeight);
    
    // Draw the wavy top edge
    double x = 0;
    while (x <= size.width) {
      // Check if we're in the bump section
      if (x >= currentCenter - radius && x <= currentCenter + radius) {
        // Calculate semicircle curve going UPWARD
        final centerRelativeX = x - currentCenter;
        final distanceSquared = radius * radius - centerRelativeX * centerRelativeX;
        
        if (distanceSquared >= 0) {
          // y gets SMALLER (goes up) as we approach center
          final y = bumpHeight - sqrt(distanceSquared);
          path.lineTo(x, y);
        } else {
          path.lineTo(x, bumpHeight);
        }
      } else {
        // Flat section at bumpHeight
        path.lineTo(x, bumpHeight);
      }
      x += 0.5;
    }
    
    // Complete the shape
    path.lineTo(size.width, bumpHeight); // Top-right
    path.lineTo(size.width, size.height); // Bottom-right
    path.lineTo(0, size.height); // Bottom-left
    path.lineTo(0, bumpHeight); // Back to top-left
    
    path.close();
    
    // Draw shadow for depth
    final shadowPaint = Paint()
      ..color = Colors.black.withValues(alpha: 0.08)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4)
      ..style = PaintingStyle.fill;
    
    canvas.drawPath(path, shadowPaint);
    
    // Draw main white shape
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(WavyBottomBarPainter oldDelegate) {
    return oldDelegate.currentIndex != currentIndex ||
        oldDelegate.previousIndex != previousIndex ||
        oldDelegate.animationValue != animationValue;
  }
}

