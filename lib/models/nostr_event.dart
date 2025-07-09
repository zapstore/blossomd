class NostrEvent {
  final String id;
  final String content;
  final int createdAt;
  final String pubkey;
  final int kind;
  final List<List<String>> tags;
  final String sig;

  NostrEvent({
    required this.id,
    required this.content,
    required this.createdAt,
    required this.pubkey,
    required this.kind,
    required this.tags,
    required this.sig,
  });

  static NostrEvent fromJson(Map<String, dynamic> json) {
    return NostrEvent(
      id: json['id'] as String,
      content: json['content'] as String,
      createdAt: json['created_at'] as int,
      pubkey: json['pubkey'] as String,
      kind: json['kind'] as int,
      tags: (json['tags'] as List)
          .map((tag) => (tag as List).cast<String>())
          .toList(),
      sig: json['sig'] as String,
    );
  }

  String getTagValue(String tagName) {
    for (final tag in tags) {
      if (tag.isNotEmpty && tag[0] == tagName && tag.length > 1) {
        return tag[1];
      }
    }
    return '';
  }

  bool hasTag(String tagName, String value) {
    return getTagValue(tagName) == value;
  }
}
