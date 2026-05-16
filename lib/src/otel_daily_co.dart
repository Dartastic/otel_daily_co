// Licensed under the Apache License, Version 2.0
// Copyright 2025, Mindful Software LLC, All rights reserved.

import 'package:dartastic_opentelemetry/dartastic_opentelemetry.dart';

import 'otel_daily_co_suppression.dart';

const _tracerName = 'dartastic_otel_libs_daily_co';

Tracer _tracer() => OTel.tracerProvider().getTracer(_tracerName);

class DailyCoResult {
  const DailyCoResult({
    this.roomName,
    this.recordingId,
    this.participantCount,
    this.audioMinutesUsed,
    this.videoMinutesUsed,
    this.region,
    this.statusCode,
  });

  /// Daily room name (URL slug).
  final String? roomName;

  /// Recording id when starting/stopping cloud recording.
  final String? recordingId;
  final int? participantCount;

  /// Daily bills per participant-minute, split audio vs video.
  /// Keep them separate so cost queries can break down by media kind.
  final int? audioMinutesUsed;
  final int? videoMinutesUsed;

  /// SFU region that served the meeting (us-east, eu-west, etc.).
  final String? region;
  final int? statusCode;
}

class DailyCoCallResult<T> {
  const DailyCoCallResult({required this.value, this.result});
  final T value;
  final DailyCoResult? result;
}

/// Wraps a Daily.co REST API call in a CLIENT span. [operation] is the
/// route key (`rooms.create`, `meeting-tokens.create`,
/// `recordings.list`, `transcripts.get`, `presence.dialin`, etc.).
Future<T> tracedDailyCo<T>({
  required String operation,
  required Future<DailyCoCallResult<T>> Function() invoke,
  String? roomName,
}) async {
  if (dailyCoInstrumentationSuppressed()) {
    final r = await invoke();
    return r.value;
  }
  final m = <String, Object>{
    'rpc.system': 'daily_co',
    'rpc.method': operation,
  };
  if (roomName != null) m['daily_co.room.name'] = roomName;

  final span = _tracer().startSpan(
    'daily.co $operation',
    kind: SpanKind.client,
    attributes: OTel.attributesFromMap(m),
  );
  try {
    final r = await invoke();
    if (r.result != null) {
      final extras = <Attribute<Object>>[];
      if (r.result!.roomName != null) {
        extras.add(OTel.attributeString(
          'daily_co.room.name',
          r.result!.roomName!,
        ));
      }
      if (r.result!.recordingId != null) {
        extras.add(OTel.attributeString(
          'daily_co.recording.id',
          r.result!.recordingId!,
        ));
      }
      if (r.result!.participantCount != null) {
        extras.add(OTel.attributeInt(
          'daily_co.participant.count',
          r.result!.participantCount!,
        ));
      }
      if (r.result!.audioMinutesUsed != null) {
        extras.add(OTel.attributeInt(
          'daily_co.audio_minutes_used',
          r.result!.audioMinutesUsed!,
        ));
      }
      if (r.result!.videoMinutesUsed != null) {
        extras.add(OTel.attributeInt(
          'daily_co.video_minutes_used',
          r.result!.videoMinutesUsed!,
        ));
      }
      if (r.result!.region != null) {
        extras.add(OTel.attributeString(
          'cloud.region',
          r.result!.region!,
        ));
      }
      if (r.result!.statusCode != null) {
        extras.add(OTel.attributeInt(
          'http.response.status_code',
          r.result!.statusCode!,
        ));
        if (r.result!.statusCode! >= 400) {
          span.setStatus(
            SpanStatusCode.Error,
            'Daily.co status ${r.result!.statusCode}',
          );
        }
      }
      if (extras.isNotEmpty) span.addAttributes(OTel.attributes(extras));
    }
    return r.value;
  } catch (e, st) {
    span.addAttributes(OTel.attributes([
      OTel.attributeString(
        ErrorResource.errorType.key,
        e.runtimeType.toString(),
      ),
    ]));
    span.recordException(e, stackTrace: st);
    span.setStatus(SpanStatusCode.Error, e.toString());
    rethrow;
  } finally {
    span.end();
  }
}
