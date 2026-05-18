import 'package:flutter/material.dart';


Widget buildFeatureTile(
    BuildContext context, {
      required String title,
      required IconData icon,
      required VoidCallback onTap,
      bool isPremium = false,
      String? subtitle,
      Color iconColor = Colors.blue,
    }) {
  return Card(
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(12),
    ),
    elevation: 2,
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Icon(
                  icon,
                  size: 28,
                  color: isPremium ? Colors.amber[700] : iconColor,
                ),
                const Spacer(),
                if (isPremium)
                  Icon(
                    Icons.workspace_premium,
                    size: 18,
                    color: Colors.amber[700],
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              title,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Colors.grey[800],
              ),
            ),
            if (subtitle != null)
              Text(
                subtitle,
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey[600],
                ),
              ),
          ],
        ),
      ),
    ),
  );
}