class UnparsedMessage {

  UnparsedMessage({
    required this.id,
    required this.content,
    required this.source,
    required this.receivedAt, this.sender,
    this.subject,
  });

  factory UnparsedMessage.fromJson(Map<String, dynamic> json) {
    return UnparsedMessage(
      id: json['id'] as String,
      content: (json['raw_content'] ?? json['content']) as String,
      source: json['source'] as String,
      sender: json['sender'] as String?,
      subject: json['subject'] as String?,
      receivedAt: DateTime.parse(
        (json['created_at'] ?? json['received_at']) as String,
      ).toLocal(),
    );
  }
  final String id;
  final String content;
  final String source;
  final String? sender;
  final String? subject;
  final DateTime receivedAt;

  Map<String, dynamic> toJson() => {
    'id': id,
    'raw_content': content,
    'source': source,
    'sender': sender,
    'subject': subject,
    'created_at': receivedAt.toUtc().toIso8601String(),
  };
}
