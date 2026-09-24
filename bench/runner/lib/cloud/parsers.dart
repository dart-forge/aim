import 'dart:io';

class UploadSize {
  const UploadSize({required this.bytes, this.gzipBytes});
  final int bytes;
  final int? gzipBytes;
  Map<String, Object?> toJson() => {'bytes': bytes, 'gzipBytes': gzipBytes};
  factory UploadSize.fromJson(Map<String, Object?> j) =>
      UploadSize(bytes: j['bytes'] as int, gzipBytes: j['gzipBytes'] as int?);
}

int _kib(String n) => (double.parse(n) * 1024).round();

/// `Total Upload: 168.06 KiB / gzip: 48.41 KiB`
UploadSize? parseWranglerUpload(String output) {
  final m = RegExp(r'Total Upload:\s*([\d.]+)\s*KiB\s*/\s*gzip:\s*([\d.]+)\s*KiB').firstMatch(output);
  if (m == null) return null;
  return UploadSize(bytes: _kib(m.group(1)!), gzipBytes: _kib(m.group(2)!));
}

Uri? parseWranglerUrl(String output) {
  final m = RegExp(r'https://[\w.-]+\.workers\.dev').firstMatch(output);
  return m == null ? null : Uri.parse(m.group(0)!);
}

/// `Function URL (benchAim(us-central1)): https://...run.app`
Uri? parseFirebaseFunctionUrl(String output, String functionName) {
  final m = RegExp('Function URL \\(${RegExp.escape(functionName)}\\([^)]*\\)\\):\\s*(https://\\S+)').firstMatch(output);
  return m == null ? null : Uri.parse(m.group(1)!);
}

Future<UploadSize> sizeOfFiles(List<File> files) async {
  var bytes = 0;
  var gz = 0;
  for (final f in files) {
    final data = await f.readAsBytes();
    bytes += data.length;
    gz += gzip.encode(data).length;
  }
  return UploadSize(bytes: bytes, gzipBytes: gz);
}

Future<int> sizeOfDirectory(Directory dir) async {
  var total = 0;
  await for (final e in dir.list(recursive: true, followLinks: false)) {
    if (e is File) total += await e.length();
  }
  return total;
}
