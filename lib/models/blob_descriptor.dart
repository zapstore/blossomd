class BlobDescriptor {
  final String sha256;
  final int size;
  final String? type;
  final int uploaded;
  final String url;

  BlobDescriptor({
    required this.sha256,
    required this.size,
    this.type,
    required this.uploaded,
    required this.url,
  });

  Map<String, dynamic> toJson() {
    return {
      'sha256': sha256,
      'size': size,
      if (type != null) 'type': type,
      'uploaded': uploaded,
      'url': url,
    };
  }
}
