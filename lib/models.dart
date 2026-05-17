import 'package:cloud_firestore/cloud_firestore.dart';

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
// LOCATION & ROOM HIERARCHY
// ─────────────────────────────────────────────────────────────────────────────

class UniLocation {
  final String lId;
  final String lName;
  final double x;
  final double y;
  final String description;
  final bool isRoom;

  UniLocation({
    required this.lId,
    required this.lName,
    required this.x,
    required this.y,
    required this.description,
    this.isRoom = false,
  });

  // Method from diagram
  String details() {
    return "Location: $lName\nDesc: $description\nCoords: ($x, $y)";
  }

  factory UniLocation.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    if (data['isRoom'] == true) {
      return Room.fromMap(data, doc.id);
    }
    return UniLocation(
      lId: doc.id,
      lName: data['L_name'] ?? '',
      x: (data['X'] ?? 0.0).toDouble(),
      y: (data['Y'] ?? 0.0).toDouble(),
      description: data['Description'] ?? '',
      isRoom: false,
    );
  }

  Map<String, dynamic> toMap() => {
        'L_name': lName,
        'X': x,
        'Y': y,
        'Description': description,
        'isRoom': isRoom,
      };
}

class Room extends UniLocation {
  final int rNo;
  final String rType;
  final int capacity;
  final int floorNo;

  Room({
    required super.lId,
    required super.lName,
    required super.x,
    required super.y,
    required super.description,
    required this.rNo,
    required this.rType,
    required this.capacity,
    required this.floorNo,
  }) : super(
          isRoom: true,
        );

  @override
  String details() {
    return "${super.details()}\nRoom No: $rNo\nType: $rType\nFloor: $floorNo";
  }

  factory Room.fromMap(Map<String, dynamic> data, String id) {
    return Room(
      lId: id,
      lName: data['L_name'] ?? '',
      x: (data['X'] ?? 0.0).toDouble(),
      y: (data['Y'] ?? 0.0).toDouble(),
      description: data['Description'] ?? '',
      rNo: data['r_no'] ?? 0,
      rType: data['r_type'] ?? '',
      capacity: data['capacity'] ?? 0,
      floorNo: data['floor_no'] ?? 0,
    );
  }

  @override
  Map<String, dynamic> toMap() {
    final map = super.toMap();
    map.addAll({
      'r_no': rNo,
      'r_type': rType,
      'capacity': capacity,
      'floor_no': floorNo,
    });
    return map;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// PATH & NAVIGATION
// ─────────────────────────────────────────────────────────────────────────────

class UniPath {
  final int pId;
  final double distance;
  final String pathType;
  final double startPoint;
  final double endPoint;

  UniPath({
    required this.pId,
    required this.distance,
    required this.pathType,
    required this.startPoint,
    required this.endPoint,
  });

  // Methods from diagram
  double getDistance() => distance;
  String getPathType() => pathType;
  List<double> getEndpoints() => [startPoint, endPoint];

  factory UniPath.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return UniPath(
      pId: int.parse(doc.id),
      distance: (data['distance'] ?? 0.0).toDouble(),
      pathType: data['pathtype'] ?? '',
      startPoint: (data['startPoint'] ?? 0.0).toDouble(),
      endPoint: (data['endPoint'] ?? 0.0).toDouble(),
    );
  }

  Map<String, dynamic> toMap() => {
        'distance': distance,
        'pathtype': pathType,
        'startPoint': startPoint,
        'endPoint': endPoint,
      };
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
