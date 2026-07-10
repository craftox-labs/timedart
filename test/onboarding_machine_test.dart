import 'package:flutter_test/flutter_test.dart';
import 'package:timedart/features/onboarding/onboarding_machine.dart';

// Pure-logic coverage for the onboarding step machine (PRD #133): step order,
// next/back clamping, skipStep advancing, skipAll jumping to complete, and the
// latch that marks complete exactly once.
void main() {
  test('starts on Welcome in the PRD step order', () {
    final m = OnboardingMachine();
    expect(m.steps, const [
      OnboardingStep.welcome,
      OnboardingStep.howItWorks,
      OnboardingStep.business,
      OnboardingStep.region,
      OnboardingStep.done,
    ]);
    expect(m.current, OnboardingStep.welcome);
    expect(m.index, 0);
    expect(m.isFirst, isTrue);
    expect(m.isLast, isFalse);
    expect(m.isComplete, isFalse);
  });

  test('next walks through every step then completes on the last', () {
    final m = OnboardingMachine();
    m.next(); // → howItWorks
    m.next(); // → business
    m.next(); // → region
    m.next(); // → done
    expect(m.current, OnboardingStep.done);
    expect(m.isLast, isTrue);
    expect(m.isComplete, isFalse); // done is a visible screen, not yet finished
    m.next(); // finish
    expect(m.isComplete, isTrue);
  });

  test('back steps backward and clamps at the first step', () {
    final m = OnboardingMachine();
    m.next(); // howItWorks
    m.next(); // business
    m.back(); // howItWorks
    expect(m.current, OnboardingStep.howItWorks);
    m.back(); // welcome
    m.back(); // clamp
    m.back();
    expect(m.current, OnboardingStep.welcome);
    expect(m.index, 0);
  });

  test('skipStep advances like next', () {
    final m = OnboardingMachine();
    m.next(); // howItWorks
    m.next(); // business
    m.skipStep(); // → region
    expect(m.current, OnboardingStep.region);
    expect(m.isComplete, isFalse);
  });

  test('skipAll completes immediately from any step', () {
    final m = OnboardingMachine();
    m.next(); // howItWorks
    m.skipAll();
    expect(m.isComplete, isTrue);
  });

  test('complete is latched: idempotent next, back cannot reopen', () {
    final m = OnboardingMachine();
    m.skipAll();
    expect(m.isComplete, isTrue);
    m.next();
    m.next();
    m.back();
    expect(m.isComplete, isTrue); // still complete, never reopened
  });
}
