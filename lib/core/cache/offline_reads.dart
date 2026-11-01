import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';

bool isConnectionFailure(Object error) =>
    error is TimeoutException ||
    error is FirebaseException &&
        const ['unavailable', 'deadline-exceeded', 'network-request-failed']
            .contains(error.code);

/// Attach the remote stream immediately; a slow disk read must not delay errors
/// or overwrite a newer server result when it eventually completes.
Stream<List<T>> cachedThenRemote<T>(
        Future<List<T>> Function() cached, Stream<List<T>> remote,
        {void Function()? onCached}) =>
    Stream.multi((out) {
      var cancelled = false, serverSeen = false, blocked = false, done = false;
      var pending = 1, remoteGeneration = 0;
      void finish() {
        if (done && pending == 0 && !cancelled) out.close();
      }

      cached()
          .then((value) {
            if (!cancelled && !blocked && !serverSeen) {
              onCached?.call();
              out.add(value);
            }
          })
          .catchError((Object _) {})
          .whenComplete(() {
            pending--;
            finish();
          });
      final subscription = remote.listen((value) {
        serverSeen = true;
        remoteGeneration++;
        if (!cancelled) out.add(value);
      }, onError: (Object error, StackTrace stack) {
        if (cancelled) return;
        if (!isConnectionFailure(error)) {
          blocked = true;
          out.addError(error, stack);
          return;
        }
        pending++;
        final generation = remoteGeneration;
        cached().then((value) {
          if (!cancelled && !blocked && generation == remoteGeneration) {
            onCached?.call();
            out.add(value);
          }
        }).catchError((Object failure, StackTrace trace) {
          if (!cancelled) out.addError(failure, trace);
        }).whenComplete(() {
          pending--;
          finish();
        });
      }, onDone: () {
        done = true;
        finish();
      });
      out.onCancel = () {
        cancelled = true;
        unawaited(subscription.cancel());
      };
    });
