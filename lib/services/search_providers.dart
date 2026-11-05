import 'dart:convert';
import 'dart:typed_data';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:speech_to_text/speech_to_text.dart';

import 'search.dart';

/// Voice search: the phone's (or browser's) own speech recogniser. Free, no server.
/// Speaks in the device language; Telugu works where the device has a Telugu recogniser.
class DeviceVoiceSearch implements VoiceSearchProvider {
  const DeviceVoiceSearch({this.localeId});
  final String? localeId;

  @override
  Future<String> transcribe() async {
    final speech = SpeechToText();
    final ok = await speech.initialize();
    if (!ok) {
      throw StateError(
        'Voice search is not available on this device or browser. Please type your search.',
      );
    }
    final words = <String>[];
    var done = false;
    await speech.listen(
      localeId: localeId,
      listenFor: const Duration(seconds: 15),
      pauseFor: const Duration(seconds: 3),
      onResult: (r) {
        words
          ..clear()
          ..add(r.recognizedWords);
        if (r.finalResult) done = true;
      },
    );
    // Wait until the speech engine says it is finished (or the 15 s limit passes).
    final end = DateTime.now().add(const Duration(seconds: 18));
    while (!done && speech.isListening && DateTime.now().isBefore(end)) {
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
    await speech.stop();
    final text = words.isEmpty ? '' : words.first.trim();
    if (text.isEmpty) {
      throw StateError('Could not hear anything. Please try again or type your search.');
    }
    return text;
  }
}

/// Photo search: the picture goes to the `describeImageForSearch` function, which
/// asks Claude what product is in it and returns a few search words.
class CloudImageSearch implements ImageSearchProvider {
  const CloudImageSearch();

  @override
  Future<String> describe(Uint8List bytes) async {
    try {
      final result = await FirebaseFunctions.instance
          .httpsCallable('describeImageForSearch')
          .call({'image': base64Encode(bytes)});
      final query = (result.data is Map ? result.data['query'] : '')?.toString().trim() ?? '';
      if (query.isEmpty) {
        throw StateError('Could not tell what is in the photo. Please type your search.');
      }
      return query;
    } on FirebaseFunctionsException catch (e) {
      throw StateError(
        e.code == 'unauthenticated'
            ? 'Please sign in to search by photo.'
            : 'Photo search is not available right now. Please type your search.',
      );
    }
  }
}
