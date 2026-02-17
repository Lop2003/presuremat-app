import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import 'package:golf_force_plate/screens/playback_screen.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  late final Stream<List<Map<String, dynamic>>> _swingsStream;
  final SupabaseClient _supabase = Supabase.instance.client;

  @override
  void initState() {
    super.initState();
    final user = _supabase.auth.currentUser;
    if (user != null) {
      _swingsStream = _supabase
          .from('swings')
          .stream(primaryKey: ['id'])
          .eq('user_id', user.id)
          .order('timestamp', ascending: false);
    } else {
      _swingsStream = Stream.value([]);
    }
  }

  Future<void> _deleteSwing(String swingId) async {
    try {
      await _supabase.from('swings').delete().eq('id', swingId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Row(
              children: [
                Icon(Icons.delete_outline, color: Colors.white, size: 16),
                SizedBox(width: 8),
                Text('Session deleted'),
              ],
            ),
            backgroundColor: Colors.redAccent.withOpacity(0.9),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Delete failed: $e'), backgroundColor: Colors.redAccent),
        );
      }
    }
  }

  void _confirmDelete(String swingId) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Delete Session', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
        content: Text('Are you sure you want to delete this swing session?',
            style: TextStyle(color: Colors.white.withOpacity(0.6))),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancel', style: TextStyle(color: Colors.white.withOpacity(0.5))),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              _deleteSwing(swingId);
            },
            child: const Text('Delete', style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        title: const Text('Swing History',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 20)),
        leading: IconButton(
          icon: Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.08),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.arrow_back_ios_new, color: Colors.white, size: 18),
          ),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: StreamBuilder<List<Map<String, dynamic>>>(
        stream: _swingsStream,
        builder: (context, snapshot) {
          // Loading State
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(color: Colors.cyanAccent, strokeWidth: 3),
            );
          }

          // Error State
          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.redAccent.withOpacity(0.1),
                      ),
                      child: const Icon(Icons.error_outline, size: 48, color: Colors.redAccent),
                    ),
                    const SizedBox(height: 16),
                    const Text('Something went wrong',
                        style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 8),
                    Text('${snapshot.error}',
                        style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 12),
                        textAlign: TextAlign.center, maxLines: 3, overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 20),
                    ElevatedButton.icon(
                      onPressed: () => setState(() {}),
                      icon: const Icon(Icons.refresh, size: 18),
                      label: const Text('Retry'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.redAccent.withOpacity(0.15),
                        foregroundColor: Colors.redAccent,
                        elevation: 0,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
                  ],
                ),
              ),
            );
          }

          // Empty State
          if (!snapshot.hasData || snapshot.data!.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(40),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.white.withOpacity(0.04),
                      ),
                      child: Icon(Icons.sports_golf, size: 56, color: Colors.white.withOpacity(0.15)),
                    ),
                    const SizedBox(height: 24),
                    const Text('No Swings Yet',
                        style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 8),
                    Text('Record a swing from the dashboard\nand it will appear here.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 13, height: 1.5)),
                    const SizedBox(height: 24),
                    SizedBox(
                      height: 44,
                      child: ElevatedButton.icon(
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.dashboard, size: 18),
                        label: const Text('Go to Dashboard'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.cyanAccent.withOpacity(0.15),
                          foregroundColor: Colors.cyanAccent,
                          elevation: 0,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          }

          final swingDocs = snapshot.data!;

          return Column(
            children: [
              // Session count header
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.cyanAccent.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text('${swingDocs.length} sessions',
                          style: const TextStyle(color: Colors.cyanAccent, fontSize: 12, fontWeight: FontWeight.w600)),
                    ),
                    const Spacer(),
                    Text('Swipe left to delete',
                        style: TextStyle(color: Colors.white.withOpacity(0.25), fontSize: 11)),
                  ],
                ),
              ),

              // List
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  itemCount: swingDocs.length,
                  itemBuilder: (context, index) {
                    final swing = swingDocs[index];
                    return _buildSwingCard(swing, index);
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildSwingCard(Map<String, dynamic> swing, int index) {
    // Parse data
    if (!swing.containsKey('timestamp') ||
        (!swing.containsKey('data_points') && !swing.containsKey('dataPoints'))) {
      return const SizedBox.shrink();
    }

    DateTime timestamp;
    try {
      timestamp = DateTime.parse(swing['timestamp']);
    } catch (e) {
      timestamp = DateTime.now();
    }

    final dataPoints = (swing['data_points'] ?? swing['dataPoints']) as List? ?? [];
    final hasVideo = swing['video_path'] != null && (swing['video_path'] as String).isNotEmpty;
    final swingId = swing['id'].toString();

    // Compute stats
    double peakLeft = 0, peakRight = 0, avgLeft = 0;
    double totalLeft = 0;
    for (var point in dataPoints) {
      if (point is Map && point.containsKey('l')) {
        final l = (point['l'] as num).toDouble();
        final r = (point['r'] as num?)?.toDouble() ?? (100 - l);
        if (l > peakLeft) peakLeft = l;
        if (r > peakRight) peakRight = r;
        totalLeft += l;
      }
    }
    if (dataPoints.isNotEmpty) avgLeft = totalLeft / dataPoints.length;

    final duration = dataPoints.isNotEmpty && dataPoints.last is Map
        ? ((dataPoints.last['t'] as num?)?.toDouble() ?? 0)
        : 0.0;

    return Dismissible(
      key: Key(swingId),
      direction: DismissDirection.endToStart,
      confirmDismiss: (_) async {
        _confirmDelete(swingId);
        return false;
      },
      background: Container(
        alignment: Alignment.centerRight,
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.only(right: 24),
        decoration: BoxDecoration(
          color: Colors.redAccent.withOpacity(0.15),
          borderRadius: BorderRadius.circular(16),
        ),
        child: const Icon(Icons.delete_outline, color: Colors.redAccent, size: 24),
      ),
      child: GestureDetector(
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => PlaybackScreen(swingId: swing['id'])),
          );
        },
        child: Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            color: const Color(0xFF1E293B),
            border: Border.all(color: Colors.white.withOpacity(0.05)),
          ),
          child: Row(
            children: [
              // Swing number badge
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Colors.cyanAccent.withOpacity(0.2), Colors.blueAccent.withOpacity(0.2)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Center(
                  child: Icon(
                    hasVideo ? Icons.videocam : Icons.show_chart,
                    color: Colors.cyanAccent,
                    size: 22,
                  ),
                ),
              ),
              const SizedBox(width: 12),

              // Date & time
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      DateFormat('MMM d, yyyy').format(timestamp),
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        Icon(Icons.access_time, size: 12, color: Colors.white.withOpacity(0.35)),
                        const SizedBox(width: 4),
                        Text(
                          DateFormat('HH:mm').format(timestamp),
                          style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 12),
                        ),
                        const SizedBox(width: 10),
                        Icon(Icons.timer_outlined, size: 12, color: Colors.white.withOpacity(0.35)),
                        const SizedBox(width: 4),
                        Text(
                          '${duration.toStringAsFixed(1)}s',
                          style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 12),
                        ),
                        if (hasVideo) ...[
                          const SizedBox(width: 10),
                          Icon(Icons.videocam, size: 12, color: Colors.greenAccent.withOpacity(0.6)),
                        ],
                      ],
                    ),
                  ],
                ),
              ),

              // Stats pill
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.cyanAccent.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '${peakLeft.toStringAsFixed(0)}%',
                      style: const TextStyle(
                        color: Colors.cyanAccent,
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
                      ),
                    ),
                    Text(
                      'Peak L',
                      style: TextStyle(color: Colors.white.withOpacity(0.35), fontSize: 9),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              Icon(Icons.chevron_right, color: Colors.white.withOpacity(0.2), size: 20),
            ],
          ),
        ),
      ),
    );
  }
}
