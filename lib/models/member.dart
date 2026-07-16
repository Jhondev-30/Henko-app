// Modelo de Miembro del Henko
class Member {
  final int? id;
  final String name;
  final DateTime createdAt;
  final bool active;
  final String? photoPath;

  const Member({
    this.id,
    required this.name,
    required this.createdAt,
    this.active = true,
    this.photoPath,
  });

  Member copyWith({
    int? id,
    String? name,
    DateTime? createdAt,
    bool? active,
    String? photoPath,
  }) {
    return Member(
      id: id ?? this.id,
      name: name ?? this.name,
      createdAt: createdAt ?? this.createdAt,
      active: active ?? this.active,
      photoPath: photoPath ?? this.photoPath,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'created_at': createdAt.millisecondsSinceEpoch,
      'active': active ? 1 : 0,
      'photo_path': photoPath,
    };
  }

  factory Member.fromMap(Map<String, dynamic> map) {
    return Member(
      id: map['id'] as int?,
      name: map['name'] as String,
      createdAt:
          DateTime.fromMillisecondsSinceEpoch(map['created_at'] as int),
      active: (map['active'] as int? ?? 1) == 1,
      photoPath: map['photo_path'] as String?,
    );
  }
}
