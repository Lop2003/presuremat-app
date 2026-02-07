import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import 'package:golf_force_plate/screens/playback_screen.dart';
import 'package:golf_force_plate/widgets/modern_app_bar.dart';
import 'package:golf_force_plate/widgets/modern_card.dart';

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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF111827),
      appBar: const ModernAppBar(title: 'Swing History'),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF111827), Color(0xFF0A0F1D)],
          ),
        ),
        child: StreamBuilder<List<Map<String, dynamic>>>(
          stream: _swingsStream,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.05),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: const CircularProgressIndicator(
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.blue),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Loading swing history...',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.7),
                        fontSize: 16,
                      ),
                    ),
                  ],
                ),
              );
            }

            if (snapshot.hasError) {
              print('Error details: ${snapshot.error}');
              return Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.error, size: 60, color: Colors.red),
                    const SizedBox(height: 16),
                    Text("Error: ${snapshot.error}"),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: () {
                        setState(() {}); // Refresh
                      },
                      child: const Text("Retry"),
                    ),
                  ],
                ),
              );
            }

            if (!snapshot.hasData || snapshot.data!.isEmpty) {
              return Center(
                child: Container(
                  padding: const EdgeInsets.all(32),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(24),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.05),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.history_toggle_off,
                          size: 80,
                          color: Colors.white24,
                        ),
                      ),
                      const SizedBox(height: 24),
                      const Text(
                        "No Swing Sessions Found",
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        "Go to the dashboard and simulate a swing to save it.",
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.7),
                          fontSize: 16,
                          height: 1.5,
                        ),
                      ),
                      const SizedBox(height: 32),
                      ElevatedButton.icon(
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.dashboard),
                        label: const Text("Go to Dashboard"),
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 24,
                            vertical: 12,
                          ),
                          backgroundColor: Colors.blue,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }

            final swingDocs = snapshot.data!;

            return ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              itemCount: swingDocs.length,
              itemBuilder: (context, index) {
                final swingData = swingDocs[index];

                // เพิ่มการตรวจสอบข้อมูล
                if (!swingData.containsKey('timestamp') ||
                    !swingData.containsKey('data_points')) {
                   // Try fallback for dataPoints (camelCase) if migration mixed up
                   if (!swingData.containsKey('dataPoints')) {
                        return const Card(
                        child: ListTile(
                        title: Text("Invalid data format"),
                        subtitle: Text("Some required fields are missing"),
                        ),
                    );
                   }
                }

                DateTime timestamp;
                try {
                    timestamp = DateTime.parse(swingData['timestamp']);
                } catch (e) {
                    timestamp = DateTime.now();
                }

                // Handle both snake_case (Supabase) and potential camelCase if legacy
                final dataPoints = (swingData['data_points'] ?? swingData['dataPoints']) as List;

                double peakLeft = 0;
                for (var point in dataPoints) {
                  // JSONB format check
                  if (point is Map && point.containsKey('l')) {
                    final leftValue = (point['l'] as num).toDouble();
                    if (leftValue > peakLeft) {
                      peakLeft = leftValue;
                    }
                  }
                }

                return ModernCard(
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (ctx) => PlaybackScreen(swingId: swingData['id']),
                      ),
                    );
                  },
                  child: Row(
                        children: [
                          Container(
                            width: 50,
                            height: 50,
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                colors: [Colors.blue, Colors.blueAccent],
                              ),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Icon(
                              Icons.show_chart,
                              color: Colors.white,
                              size: 28,
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  DateFormat(
                                    'EEEE, MMM d, yyyy',
                                  ).format(timestamp),
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  DateFormat('hh:mm a').format(timestamp),
                                  style: TextStyle(
                                    color: Colors.white.withOpacity(0.7),
                                    fontSize: 14,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.blue.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: Colors.blue.withOpacity(0.2),
                              ),
                            ),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text(
                                  "Peak Left",
                                  style: TextStyle(
                                    color: Colors.white.withOpacity(0.7),
                                    fontSize: 12,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  '${peakLeft.toStringAsFixed(1)}%',
                                  style: const TextStyle(
                                    color: Colors.cyanAccent,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}
