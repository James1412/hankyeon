import 'dart:io';

/// Process 연습용 서비스. 실제 Safari 연결 서비스는 아직 아닙니다.
class ProcessPracticeService {
  Future<String> fetchTitle() async {
    final result = await Process.run('/bin/echo', ['외부 프로그램에서 받은 제목']);

    if (result.exitCode != 0) {
      throw ProcessException(
        '/bin/echo',
        [],
        result.stderr.toString(),
        result.exitCode,
      );
    }

    return result.stdout.toString().trim();
  }
}
