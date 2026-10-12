import 'package:flutter/material.dart';

import '../services/process_practice_service.dart';

class ProcessPracticeScreen extends StatefulWidget {
  const ProcessPracticeScreen({super.key});

  @override
  State<ProcessPracticeScreen> createState() => _ProcessPracticeScreenState();
}

class _ProcessPracticeScreenState extends State<ProcessPracticeScreen> {
  final _service = ProcessPracticeService();
  String _title = '외부 프로그램에서 제목 가져오기';
  bool _isLoading = false;

  Future<void> _loadTitle() async {
    setState(() {
      _isLoading = true;
      _title = '기다리는 중…';
    });

    try {
      final title = await _service.fetchTitle();
      if (!mounted) return;
      setState(() => _title = title);
    } catch (error) {
      if (!mounted) return;
      setState(() => _title = '실행 실패: $error');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: TextButton(
          onPressed: _isLoading ? null : _loadTitle,
          child: Text(_title),
        ),
      ),
    );
  }
}
