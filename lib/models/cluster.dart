class FeNode {
  final String hostname;
  final String ip;

  const FeNode({required this.hostname, required this.ip});

  factory FeNode.fromMap(Map<String, dynamic> map) {
    return FeNode(
      hostname: (map['hostname'] ?? '') as String,
      ip: (map['ip'] ?? '') as String,
    );
  }

  Map<String, dynamic> toFirestoreMap() {
    return {
      'hostname': {'stringValue': hostname},
      'ip': {'stringValue': ip},
    };
  }

  factory FeNode.fromFirestoreMap(Map<String, dynamic> map) {
    return FeNode(
      hostname: map['hostname']?['stringValue']?.toString() ?? '',
      ip: map['ip']?['stringValue']?.toString() ?? '',
    );
  }

  Map<String, dynamic> toJsonMap() {
    return {
      'hostname': hostname,
      'ip': ip,
    };
  }

  factory FeNode.fromJsonMap(Map<String, dynamic> map) {
    return FeNode(
      hostname: (map['hostname'] ?? '') as String,
      ip: (map['ip'] ?? '') as String,
    );
  }

  @override
  String toString() => '$hostname ($ip)';
}

class Site {
  final String name;
  final List<FeNode> feNodes;
  final double? latitude;
  final double? longitude;
  final String? city;
  final String? province;

  const Site({
    required this.name,
    required this.feNodes,
    this.latitude,
    this.longitude,
    this.city,
    this.province,
  });

  factory Site.fromMap(Map<String, dynamic> map) {
    final nodesRaw = map['fe_nodes'];
    final nodes = (nodesRaw is List)
        ? nodesRaw
            .map((n) => FeNode.fromMap(Map<String, dynamic>.from(n as Map)))
            .toList()
        : <FeNode>[];
    final lat = map['lat'] ?? map['latitude'];
    final lon = map['lon'] ?? map['longitude'];
    return Site(
      name: (map['name'] ?? '') as String,
      feNodes: nodes,
      latitude: lat != null ? (lat as num).toDouble() : null,
      longitude: lon != null ? (lon as num).toDouble() : null,
      city: map['city'] as String?,
      province: (map['province'] ?? map['propinsi']) as String?,
    );
  }

  Map<String, dynamic> toFirestoreMap() {
    final Map<String, dynamic> fields = {
      'name': {'stringValue': name},
      'fe_nodes': {
        'arrayValue': {
          'values': feNodes
              .map((node) => {'mapValue': {'fields': node.toFirestoreMap()}})
              .toList(),
        },
      },
    };

    if (city != null && city!.isNotEmpty) {
      fields['city'] = {'stringValue': city};
    }
    if (province != null && province!.isNotEmpty) {
      fields['province'] = {'stringValue': province};
    }
    if (latitude != null) {
      fields['latitude'] = {'doubleValue': latitude};
    }
    if (longitude != null) {
      fields['longitude'] = {'doubleValue': longitude};
    }

    return fields;
  }

  factory Site.fromFirestoreMap(Map<String, dynamic> map) {
    final rawNodes = map['fe_nodes']?['arrayValue']?['values'] as List? ?? [];
    final nodes = rawNodes.map((n) {
      final fields = n['mapValue']?['fields'] as Map<String, dynamic>? ?? {};
      return FeNode.fromFirestoreMap(fields);
    }).toList();

    return Site(
      name: map['name']?['stringValue']?.toString() ?? '',
      feNodes: nodes,
      city: map['city']?['stringValue']?.toString(),
      province: map['province']?['stringValue']?.toString(),
      latitude: map['latitude']?['doubleValue'] != null
          ? (map['latitude']['doubleValue'] as num).toDouble()
          : null,
      longitude: map['longitude']?['doubleValue'] != null
          ? (map['longitude']['doubleValue'] as num).toDouble()
          : null,
    );
  }

  Map<String, dynamic> toJsonMap() {
    final map = <String, dynamic>{
      'name': name,
      'fe_nodes': feNodes.map((n) => n.toJsonMap()).toList(),
    };
    if (city != null) map['city'] = city;
    if (province != null) map['province'] = province;
    if (latitude != null) map['latitude'] = latitude;
    if (longitude != null) map['longitude'] = longitude;
    return map;
  }

  factory Site.fromJsonMap(Map<String, dynamic> map) {
    final nodesRaw = map['fe_nodes'] as List? ?? [];
    final nodes = nodesRaw
        .map((n) => FeNode.fromJsonMap(Map<String, dynamic>.from(n as Map)))
        .toList();
    return Site(
      name: (map['name'] ?? '') as String,
      feNodes: nodes,
      city: map['city'] as String?,
      province: map['province'] as String?,
      latitude: map['latitude'] != null ? (map['latitude'] as num).toDouble() : null,
      longitude: map['longitude'] != null ? (map['longitude'] as num).toDouble() : null,
    );
  }
}

class Cluster {
  final String name;
  final String oam1;
  final String oam2;
  final List<Site> sites;

  const Cluster({
    required this.name,
    required this.oam1,
    required this.oam2,
    required this.sites,
  });

  factory Cluster.fromMap(Map<String, dynamic> map) {
    final sitesRaw = map['sites'];
    final sites = (sitesRaw is List)
        ? sitesRaw
            .map((s) => Site.fromMap(Map<String, dynamic>.from(s as Map)))
            .toList()
        : <Site>[];
    return Cluster(
      name: (map['name'] ?? '') as String,
      oam1: (map['oam1'] ?? '') as String,
      oam2: (map['oam2'] ?? '') as String,
      sites: sites,
    );
  }

  Map<String, dynamic> toFirestoreMap() {
    return {
      'name': {'stringValue': name},
      'oam1': {'stringValue': oam1},
      'oam2': {'stringValue': oam2},
      'sites': {
        'arrayValue': {
          'values': sites
              .map((site) => {'mapValue': {'fields': site.toFirestoreMap()}})
              .toList(),
        },
      },
    };
  }

  factory Cluster.fromFirestoreMap(Map<String, dynamic> map) {
    final rawSites = map['sites']?['arrayValue']?['values'] as List? ?? [];
    final parsedSites = rawSites.map((s) {
      final fields = s['mapValue']?['fields'] as Map<String, dynamic>? ?? {};
      return Site.fromFirestoreMap(fields);
    }).toList();

    return Cluster(
      name: map['name']?['stringValue']?.toString() ?? '',
      oam1: map['oam1']?['stringValue']?.toString() ?? '',
      oam2: map['oam2']?['stringValue']?.toString() ?? '',
      sites: parsedSites,
    );
  }

  static Map<String, dynamic> clustersToFirestoreFields(List<Cluster> clusters) {
    return {
      'clusters': {
        'arrayValue': {
          'values': clusters
              .map((c) => {'mapValue': {'fields': c.toFirestoreMap()}})
              .toList(),
        },
      },
    };
  }

  static List<Cluster> listFromFirestoreDocument(Map<String, dynamic> doc) {
    final fields = doc['fields'] as Map<String, dynamic>? ?? doc;
    final clustersArray = fields['clusters']?['arrayValue']?['values'] as List? ?? [];
    return clustersArray.map((c) {
      final mapValue = c['mapValue']?['fields'] as Map<String, dynamic>? ?? {};
      return Cluster.fromFirestoreMap(mapValue);
    }).toList();
  }

  Map<String, dynamic> toJsonMap() {
    return {
      'name': name,
      'oam1': oam1,
      'oam2': oam2,
      'sites': sites.map((s) => s.toJsonMap()).toList(),
    };
  }

  factory Cluster.fromJsonMap(Map<String, dynamic> map) {
    final sitesRaw = map['sites'] as List? ?? [];
    final sites = sitesRaw
        .map((s) => Site.fromJsonMap(Map<String, dynamic>.from(s as Map)))
        .toList();
    return Cluster(
      name: (map['name'] ?? '') as String,
      oam1: (map['oam1'] ?? '') as String,
      oam2: (map['oam2'] ?? '') as String,
      sites: sites,
    );
  }
}
