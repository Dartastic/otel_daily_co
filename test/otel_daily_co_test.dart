// Licensed under the Apache License, Version 2.0
// Copyright 2025, Mindful Software LLC, All rights reserved.

import 'package:dartastic_opentelemetry/dartastic_opentelemetry.dart';
import 'package:dartastic_opentelemetry/testing.dart';
import 'package:otel_daily_co/otel_daily_co.dart';
import 'package:test/test.dart';

void main() {
  late TestHarness harness;
  late InMemorySpanExporter spans;

  setUpAll(() async {
    harness = await maybeInitializeOtelForTest(
      serviceName: 'otel_daily_co-test',
    );
    spans = harness.spans;
  });

  setUp(() => harness.clear());

  Map<String, Object> attrsOf(Span s) =>
      {for (final a in s.attributes.toList()) a.key: a.value};

  test('rooms.create records participant + minutes by media', () async {
    await tracedDailyCo<String>(
      operation: 'rooms.create',
      invoke: () async => const DailyCoCallResult(
        value: 'ok',
        result: DailyCoResult(
          roomName: 'standup-2026-05-14',
          participantCount: 6,
          audioMinutesUsed: 180,
          videoMinutesUsed: 150,
          region: 'us-west-2',
          statusCode: 200,
        ),
      ),
    );
    final a = attrsOf(spans.findSpanByName('daily.co rooms.create')!);
    expect(a['rpc.system'], 'daily_co');
    expect(a['daily_co.room.name'], 'standup-2026-05-14');
    expect(a['daily_co.participant.count'], 6);
    expect(a['daily_co.audio_minutes_used'], 180);
    expect(a['daily_co.video_minutes_used'], 150);
    expect(a['cloud.region'], 'us-west-2');
  });

  test('429 sets span error', () async {
    await tracedDailyCo<String>(
      operation: 'meeting-tokens.create',
      invoke: () async => const DailyCoCallResult(
        value: 'ok',
        result: DailyCoResult(statusCode: 429),
      ),
    );
    expect(
      spans.findSpanByName('daily.co meeting-tokens.create')!.status,
      SpanStatusCode.Error,
    );
  });

  test('suppression skips spans', () async {
    await runWithoutDailyCoInstrumentationAsync(() async {
      await tracedDailyCo<String>(
        operation: 'rooms.list',
        invoke: () async => const DailyCoCallResult(value: 'v'),
      );
    });
    expect(spans.findSpansStartingWith('daily.co '), isEmpty);
  });
}
