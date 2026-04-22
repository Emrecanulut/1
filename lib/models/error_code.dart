class ErrorCode {
  const ErrorCode({
    required this.code,
    required this.title,
    required this.description,
    required this.solution,
    required this.expertNote,
  });

  final String code;
  final String title;
  final String description;
  final String solution;
  final String expertNote;

  factory ErrorCode.fromMap(Map<String, dynamic> map) {
    return ErrorCode(
      code: (map['code'] as String? ?? '').trim(),
      title: (map['title'] as String? ?? '').trim(),
      description: (map['description'] as String? ?? '').trim(),
      solution: (map['solution'] as String? ?? '').trim(),
      expertNote: (map['expert_note'] as String? ?? '').trim(),
    );
  }

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'code': code,
      'title': title,
      'description': description,
      'solution': solution,
      'expert_note': expertNote,
    };
  }
}
