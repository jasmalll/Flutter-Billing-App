import 'dart:convert';

/// A catalog item. Master items are copied into every station allocation.
class InventoryItem {
  final String id;
  String name;
  int totalQuantity;
  final bool isMaster;

  InventoryItem({
    required this.id,
    required this.name,
    this.totalQuantity = 0,
    this.isMaster = true,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'totalQuantity': totalQuantity,
        'isMaster': isMaster,
      };

  factory InventoryItem.fromMap(Map<String, dynamic> map) => InventoryItem(
        id: map['id']?.toString() ?? DateTime.now().microsecondsSinceEpoch.toString(),
        name: map['name']?.toString() ?? 'Item',
        totalQuantity: (map['totalQuantity'] as num?)?.toInt() ?? 0,
        isMaster: map['isMaster'] as bool? ?? true,
      );
}

class StationAllocation {
  final String itemId;
  String itemName;
  int quantity;
  final bool isCustom;

  StationAllocation({
    required this.itemId,
    required this.itemName,
    this.quantity = 0,
    this.isCustom = false,
  });

  Map<String, dynamic> toMap() => {
        'itemId': itemId,
        'itemName': itemName,
        'quantity': quantity,
        'isCustom': isCustom,
      };

  factory StationAllocation.fromMap(Map<String, dynamic> map) => StationAllocation(
        itemId: map['itemId']?.toString() ?? '',
        itemName: map['itemName']?.toString() ?? 'Item',
        quantity: (map['quantity'] as num?)?.toInt() ?? 0,
        isCustom: map['isCustom'] as bool? ?? false,
      );
}

class CounterStation {
  final String id;
  String name;
  List<StationAllocation> allocations;

  CounterStation({required this.id, required this.name, List<StationAllocation>? allocations})
      : allocations = allocations ?? [];

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'allocations': allocations.map((e) => e.toMap()).toList(),
      };

  factory CounterStation.fromMap(Map<String, dynamic> map) => CounterStation(
        id: map['id']?.toString() ?? DateTime.now().microsecondsSinceEpoch.toString(),
        name: map['name']?.toString() ?? 'Counter',
        allocations: (map['allocations'] as List<dynamic>? ?? [])
            .whereType<Map>()
            .map((e) => StationAllocation.fromMap(Map<String, dynamic>.from(e)))
            .toList(),
      );
}

class InventoryState {
  List<InventoryItem> masterItems;
  List<CounterStation> stations;
  DateTime updatedAt;

  InventoryState({List<InventoryItem>? masterItems, List<CounterStation>? stations, DateTime? updatedAt})
      : masterItems = masterItems ?? [],
        stations = stations ?? [],
        updatedAt = updatedAt ?? DateTime.now();

  Map<String, dynamic> toMap() => {
        'masterItems': masterItems.map((e) => e.toMap()).toList(),
        'stations': stations.map((e) => e.toMap()).toList(),
        'updatedAt': updatedAt.toIso8601String(),
      };

  String toJson() => jsonEncode(toMap());

  factory InventoryState.fromJson(String source) {
    final map = Map<String, dynamic>.from(jsonDecode(source) as Map);
    return InventoryState(
      masterItems: (map['masterItems'] as List<dynamic>? ?? [])
          .whereType<Map>()
          .map((e) => InventoryItem.fromMap(Map<String, dynamic>.from(e)))
          .toList(),
      updatedAt: DateTime.tryParse(map['updatedAt']?.toString() ?? '') ?? DateTime.fromMillisecondsSinceEpoch(0),
      stations: (map['stations'] as List<dynamic>? ?? [])
          .whereType<Map>()
          .map((e) => CounterStation.fromMap(Map<String, dynamic>.from(e)))
          .toList(),
    );
  }
}
