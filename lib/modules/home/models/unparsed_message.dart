class UnparsedMessage {
  final String id;
  final String content;
  final String source;
  final String? sender;
  final String? subject;
  final DateTime receivedAt;

  UnparsedMessage({
    required this.id,
    required this.content,
    required this.source,
    this.sender,
    this.subject,
    required this.receivedAt,
  });

  factory UnparsedMessage.fromJson(Map<String, dynamic> json) {
    return UnparsedMessage(
      id: json['id'],
      content: json['raw_content'] ?? json['content'],
      source: json['source'],
      sender: json['sender'],
      subject: json['subject'],
      receivedAt: DateTime.parse(
        json['created_at'] ?? json['received_at'],
      ).toLocal(),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'raw_content': content,
    'source': source,
    'sender': sender,
    'subject': subject,
    'created_at': receivedAt.toUtc().toIso8601String(),
  };
}
