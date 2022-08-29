// ignore_for_file: always_specify_types

import 'dart:async';
import 'dart:collection';

class TaskRunner<A, B> {
  final Queue<A> _input = Queue<A>();
  final StreamController<B> _streamController = StreamController<B>();
  final Future<B> Function(A) task;

  final int maxConcurrentTasks;
  int runningTasks = 0;

  TaskRunner(this.task, {this.maxConcurrentTasks = 5});

  Stream<B> get stream => _streamController.stream;

  void add(A value) {
    _input.add(value);
    // _startExecution();
  }

  void addAll(Iterable<A> iterable) {
    _input.addAll(iterable);
    // _startExecution();
  }

  void startExecution() {
    if (runningTasks == maxConcurrentTasks || _input.isEmpty) {
      return;
    }

    while (_input.isNotEmpty && runningTasks < maxConcurrentTasks) {
      runningTasks++;

      task(_input.removeFirst()).then((value) async {
        _streamController.add(value);

        while (_input.isNotEmpty) {
          _streamController.add(await task(_input.removeFirst()));
        }

        runningTasks--;
      });
    }
  }
}
