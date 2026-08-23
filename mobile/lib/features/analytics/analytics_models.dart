class ProgressPoint {
  const ProgressPoint({required this.day, required this.totalVolume, required this.maxWeight, required this.setCount});

  final DateTime day;
  final double totalVolume;
  final double maxWeight;
  final int setCount;

  factory ProgressPoint.fromJson(Map<String, dynamic> json) => ProgressPoint(
        day: DateTime.parse(json['day'] as String),
        totalVolume: (json['totalVolume'] as num).toDouble(),
        maxWeight: (json['maxWeight'] as num).toDouble(),
        setCount: json['setCount'] as int,
      );
}

class BodyMetric {
  const BodyMetric({required this.id, required this.metricType, required this.value, required this.recordedAt});

  final String id;
  final String metricType;
  final double value;
  final DateTime recordedAt;

  factory BodyMetric.fromJson(Map<String, dynamic> json) => BodyMetric(
        id: json['id'] as String,
        metricType: json['metricType'] as String,
        value: (json['value'] as num).toDouble(),
        recordedAt: DateTime.parse(json['recordedAt'] as String),
      );
}
