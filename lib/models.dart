
// ─────────────────────────────────────────────────────────────────────────────
// USER HIERARCHY
// ─────────────────────────────────────────────────────────────────────────────

abstract class UniUser {
  final String id;
  final String role; // 'Student', 'Faculty', or 'Guest'

  UniUser({required this.id, required this.role});

  // Common method from diagram
  Future<Map<String, double>> getCurrentLocation();

  Map<String, dynamic> toMap() => {
        'id': id,
        'role': role,
      };
}

class Student extends UniUser {
  final String name;
  final String password;

  Student({
    required super.id,
    required this.name,
    required this.password,
  }) : super(role: 'Student');

  // Logic for diagram methods
  bool validateCredentials(String inputId, String inputPassword) {
    return id == inputId && password == inputPassword;
  }

  @override
  Future<Map<String, double>> getCurrentLocation() async {
    // This would typically interface with Geolocator
    return {'X': 0.0, 'Y': 0.0};
  }

  @override
  Map<String, dynamic> toMap() {
    final map = super.toMap();
    map.addAll({
      'name': name,
      'password': password,
    });
    return map;
  }
}

class Faculty extends UniUser {
  final String name;
  final String password;

  Faculty({
    required super.id,
    required this.name,
    required this.password,
  }) : super(role: 'Faculty');

  @override
  Future<Map<String, double>> getCurrentLocation() async {
    return {'X': 0.0, 'Y': 0.0};
  }

  @override
  Map<String, dynamic> toMap() {
    final map = super.toMap();
    map.addAll({
      'name': name,
      'password': password,
    });
    return map;
  }
}

class Guest extends UniUser {
  Guest({required super.id}) : super(role: 'Guest');

  void temporarySession() {
    // Logic for guest session limit (already implemented in main.dart)
  }

  @override
  Future<Map<String, double>> getCurrentLocation() async {
    return {'X': 0.0, 'Y': 0.0};
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// NAVIGATION MODELS
// ─────────────────────────────────────────────────────────────────────────────

class NavPoint {
  final double latitude;
  final double longitude;
  final int floor;

  NavPoint({
    required this.latitude,
    required this.longitude,
    required this.floor,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is NavPoint &&
          latitude == other.latitude &&
          longitude == other.longitude &&
          floor == other.floor;

  @override
  int get hashCode => latitude.hashCode ^ longitude.hashCode ^ floor.hashCode;

  @override
  String toString() => 'NavPoint(lat: $latitude, lng: $longitude, floor: $floor)';
}

class TransitionPoint {
  final double latitude;
  final double longitude;
  final bool isLift;

  TransitionPoint({
    required this.latitude,
    required this.longitude,
    required this.isLift,
  });

  @override
  String toString() => 'TransitionPoint(lat: $latitude, lng: $longitude, isLift: $isLift)';
}
