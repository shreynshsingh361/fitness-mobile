import 'dart:math' as math;

import 'package:flutter/material.dart';

/// A small, looping clip of an exercise: a minimal figure moves through the lift, and the
/// muscles it trains glow brighter as they contract.
///
/// Nothing here is an image or a video. Each exercise is two poses (start and end) of a
/// stick figure with fixed limb lengths, and the painter moves between them in a 3.6 second
/// loop: a short pause, the lift, a pause at the top, a slower way back.
///
/// Angles are in degrees on the screen: 0 points right (where the figure faces), 90 down,
/// -90 up and 180 left. The backend tells which motion an exercise uses (its `motion`).

enum Muscle { chest, back, lowerBack, abs, shoulders, biceps, triceps, forearms, quads, hamstrings, glutes, calves }

/// The point of the body that stays put while the rest moves: feet on the floor, hands on
/// a bar, hips on a seat.
enum Anchor { hip, foot, toe, hand }

/// Which side of the shin a machine's roller presses on.
enum Roller { none, front, back }

class Pose {
  const Pose({
    this.torso = -90,
    this.upper = 90,
    this.fore = 90,
    this.thigh = 90,
    this.shin = 90,
    this.foot = 0,
    this.reach = 1,
    this.upper2,
    this.fore2,
    this.thigh2,
    this.shin2,
    this.foot2,
    this.wrist,
  });

  final double torso; // hip → shoulder
  final double upper; // shoulder → elbow
  final double fore; // elbow → hand
  final double thigh; // hip → knee
  final double shin; // knee → ankle
  final double foot; // ankle → toe
  final double reach; // how much of the arm shows: an arm pointing at the viewer looks short

  // The far arm and leg. Null: the same as the near one (side view) or its mirror image
  // (front view).
  final double? upper2;
  final double? fore2;
  final double? thigh2;
  final double? shin2;
  final double? foot2;

  // The hand, from the wrist. Null: in line with the forearm. Only wrist exercises bend it.
  final double? wrist;
}

/// A rectangle standing on the floor, such as a bench or a seat: x from [left] to [right],
/// top at [top].
class Block {
  const Block(this.left, this.right, this.top);

  final double left;
  final double right;
  final double top;
}

/// A fixed bar or pad, from [a] to [b].
class Pad {
  const Pad(this.a, this.b, {this.width = 6});

  final Offset a;
  final Offset b;
  final double width;
}

class Motion {
  const Motion(
    this.start,
    this.end, {
    required this.muscles,
    this.anchor = Anchor.foot,
    this.front = false,
    this.foreshorten = false,
    this.floor = true,
    this.blocks = const [],
    this.pads = const [],
    this.cable,
    this.barAtHand = false,
    this.footPlate = false,
    this.roller = Roller.none,
    this.wheel = false,
  });

  final Pose start;
  final Pose end; // where the muscles are most contracted
  final List<Muscle> muscles;
  final Anchor anchor;
  final bool front; // seen from the front instead of the side
  // Arms move as straight lines between the poses instead of turning at the shoulder, so an
  // elbow that travels towards the viewer (a pull-up, a press) passes in front of the body.
  final bool foreshorten;
  final bool floor;
  final List<Block> blocks;
  final List<Pad> pads;
  final Offset? cable; // the pulley; the cable runs from it to the hand
  final bool barAtHand; // a pull-up bar or dip bars, where the hands hold on
  final bool footPlate; // a leg press platform under the feet
  final Roller roller;
  final bool wheel; // an ab wheel under the hands
}

/// The motion of each kind of exercise, by the name the backend uses.
/// Coordinates are around the hip of the start pose, at (0, 0).
const motions = <String, Motion>{
  // ---------- back ----------
  'deadlift': Motion(
    Pose(torso: -38, thigh: 28, shin: 108),
    Pose(),
    muscles: [Muscle.lowerBack, Muscle.glutes, Muscle.hamstrings],
  ),
  'rdl': Motion(Pose(torso: -15, thigh: 75, shin: 95), Pose(), muscles: [Muscle.hamstrings, Muscle.glutes]),
  'row': Motion(
    Pose(torso: -35, thigh: 70, shin: 105),
    Pose(torso: -35, thigh: 70, shin: 105, upper: 195, fore: 95),
    muscles: [Muscle.back],
  ),
  'pullup': Motion(
    Pose(upper: -90, fore: -90, thigh: 92, shin: 108),
    Pose(upper: 110, fore: -70, thigh: 92, shin: 108),
    muscles: [Muscle.back, Muscle.biceps],
    anchor: Anchor.hand,
    foreshorten: true,
    floor: false,
    barAtHand: true,
  ),
  'pulldown': Motion(
    Pose(torso: -100, upper: -82, fore: -88, thigh: 0, shin: 95),
    Pose(torso: -100, upper: 110, fore: -70, thigh: 0, shin: 95),
    muscles: [Muscle.back],
    anchor: Anchor.hip,
    foreshorten: true,
    blocks: [Block(-16, 18, 7)],
    cable: Offset(4, -150),
  ),
  'cable_row': Motion(
    Pose(torso: -72, upper: 2, fore: 2, thigh: -8, shin: 8, foot: -80),
    Pose(torso: -95, upper: 160, fore: -5, thigh: -8, shin: 8, foot: -80),
    muscles: [Muscle.back],
    anchor: Anchor.hip,
    blocks: [Block(-18, 60, 7)],
    pads: [Pad(Offset(78, -14), Offset(78, 14), width: 5)],
    cable: Offset(122, -22),
  ),
  'straight_pulldown': Motion(
    Pose(torso: -75, upper: -40, fore: -40, thigh: 85, shin: 95),
    Pose(torso: -75, upper: 100, fore: 100, thigh: 85, shin: 95),
    muscles: [Muscle.back],
    cable: Offset(78, -120),
  ),

  // ---------- biceps ----------
  'curl': Motion(Pose(upper: 92, fore: 92), Pose(upper: 85, fore: -70), muscles: [Muscle.biceps, Muscle.forearms]),
  'cable_curl': Motion(
    Pose(upper: 92, fore: 92),
    Pose(upper: 85, fore: -70),
    muscles: [Muscle.biceps],
    cable: Offset(44, 70),
  ),
  'preacher': Motion(
    Pose(torso: -75, upper: 55, fore: 62, thigh: 0, shin: 95),
    Pose(torso: -75, upper: 55, fore: -95, thigh: 0, shin: 95),
    muscles: [Muscle.biceps],
    anchor: Anchor.hip,
    blocks: [Block(-16, 16, 7)],
    pads: [Pad(Offset(8, -41), Offset(24, -19), width: 7)],
  ),
  'concentration': Motion(
    Pose(torso: -55, upper: 95, fore: 95, thigh: 0, shin: 92),
    Pose(torso: -55, upper: 95, fore: -60, thigh: 0, shin: 92),
    muscles: [Muscle.biceps],
    anchor: Anchor.hip,
    blocks: [Block(-16, 16, 7)],
  ),

  // ---------- triceps ----------
  'pushdown': Motion(
    Pose(torso: -82, upper: 100, fore: -35, thigh: 88, shin: 92),
    Pose(torso: -82, upper: 95, fore: 88, thigh: 88, shin: 92),
    muscles: [Muscle.triceps],
    cable: Offset(32, -125),
  ),
  'overhead_ext': Motion(Pose(upper: -100, fore: 125), Pose(upper: -100, fore: 265), muscles: [Muscle.triceps]),
  'skull': Motion(
    Pose(torso: 180, upper: -100, fore: 145, thigh: -20, shin: 95),
    Pose(torso: 180, upper: -100, fore: 260, thigh: -20, shin: 95),
    muscles: [Muscle.triceps],
    anchor: Anchor.hip,
    blocks: [Block(-60, 12, 8)],
  ),
  'bench_dip': Motion(
    Pose(upper: 100, fore: 95, thigh: 30, shin: 85),
    Pose(torso: -88, upper: 175, fore: 80, thigh: 0, shin: 60),
    muscles: [Muscle.triceps],
    anchor: Anchor.hand,
    blocks: [Block(-42, -3, 4.5)],
  ),

  // ---------- chest ----------
  'bench': Motion(
    Pose(torso: 180, upper: 75, fore: -95, thigh: -20, shin: 95),
    Pose(torso: 180, upper: -90, fore: -90, thigh: -20, shin: 95),
    muscles: [Muscle.chest, Muscle.triceps],
    anchor: Anchor.hip,
    foreshorten: true,
    blocks: [Block(-60, 12, 8)],
  ),
  'incline': Motion(
    Pose(torso: -145, upper: 115, fore: -50, thigh: 10, shin: 90),
    Pose(torso: -145, upper: -55, fore: -55, thigh: 10, shin: 90),
    muscles: [Muscle.chest, Muscle.shoulders],
    anchor: Anchor.hip,
    foreshorten: true,
    blocks: [Block(-16, 16, 7)],
    pads: [Pad(Offset(-5, 7), Offset(-46, -22), width: 7)],
  ),
  'fly_lying': Motion(
    Pose(torso: 180, upper: 80, fore: 70, thigh: -20, shin: 95),
    Pose(torso: 180, upper: -88, fore: -95, thigh: -20, shin: 95),
    muscles: [Muscle.chest],
    anchor: Anchor.hip,
    foreshorten: true,
    blocks: [Block(-60, 12, 8)],
  ),
  'fly': Motion(
    Pose(upper: -10, fore: -5, thigh: 86, shin: 90),
    Pose(upper: 115, fore: 100, thigh: 86, shin: 90),
    muscles: [Muscle.chest],
    front: true,
    cable: Offset(82, -112),
  ),
  'pushup': Motion(
    Pose(torso: -23.6, thigh: 156.4, shin: 156.4, foot: 100),
    Pose(torso: -15, upper: 140, fore: 45, thigh: 165, shin: 165, foot: 100),
    muscles: [Muscle.chest, Muscle.triceps],
    anchor: Anchor.hand,
  ),
  'dip': Motion(
    Pose(torso: -75, upper: 95, fore: 90, thigh: 100, shin: 140),
    Pose(torso: -60, upper: 165, fore: 70, thigh: 100, shin: 140),
    muscles: [Muscle.chest, Muscle.triceps],
    anchor: Anchor.hand,
    floor: false,
    barAtHand: true,
  ),
  'chest_press': Motion(
    Pose(torso: -95, upper: 165, fore: 5, thigh: 0, shin: 95),
    Pose(torso: -95, upper: 3, fore: 0, thigh: 0, shin: 95),
    muscles: [Muscle.chest, Muscle.triceps],
    anchor: Anchor.hip,
    blocks: [Block(-16, 16, 7)],
    pads: [Pad(Offset(-12, 6), Offset(-17, -50), width: 7)],
  ),

  // ---------- legs ----------
  'squat': Motion(
    Pose(torso: -88, upper: 150, fore: -75),
    Pose(torso: -50, upper: 175, fore: -60, thigh: 5, shin: 120),
    muscles: [Muscle.quads, Muscle.glutes],
  ),
  'leg_press': Motion(
    Pose(torso: -150, upper: 60, fore: 20, thigh: -95, shin: 15, foot: -130),
    Pose(torso: -150, upper: 60, fore: 20, thigh: -40, shin: -40, foot: -130),
    muscles: [Muscle.quads, Muscle.glutes],
    anchor: Anchor.hip,
    footPlate: true,
    pads: [Pad(Offset(-4, 8), Offset(-46, -17), width: 7)],
  ),
  'lunge': Motion(
    Pose(thigh: 59, shin: 59, thigh2: 121, shin2: 121, foot2: 70),
    Pose(torso: -85, thigh: 15, shin: 90, thigh2: 95, shin2: 175, foot2: 80),
    muscles: [Muscle.quads, Muscle.glutes],
  ),
  'leg_extension': Motion(
    Pose(torso: -95, upper: 100, fore: 60, thigh: 0, shin: 95),
    Pose(torso: -95, upper: 100, fore: 60, thigh: 0, shin: 5, foot: -80),
    muscles: [Muscle.quads],
    anchor: Anchor.hip,
    blocks: [Block(-16, 30, 7)],
    roller: Roller.front,
  ),
  'leg_curl': Motion(
    Pose(torso: -95, upper: 100, fore: 60, thigh: 0, shin: 5, foot: -80),
    Pose(torso: -95, upper: 100, fore: 60, thigh: 0, shin: 100),
    muscles: [Muscle.hamstrings],
    anchor: Anchor.hip,
    blocks: [Block(-16, 30, 7)],
    roller: Roller.back,
  ),
  'calf_raise': Motion(Pose(foot: 10), Pose(foot: 45), muscles: [Muscle.calves], anchor: Anchor.toe),

  // ---------- abs ----------
  'crunch': Motion(
    Pose(torso: 180, upper: -110, fore: 104, thigh: -55, shin: 65),
    Pose(torso: 215, upper: -75, fore: 139, thigh: -55, shin: 65),
    muscles: [Muscle.abs],
    anchor: Anchor.hip,
  ),
  'leg_raise': Motion(
    Pose(torso: 180, upper: 0, fore: 0, thigh: -5, shin: -5, foot: -80),
    Pose(torso: 180, upper: 0, fore: 0, thigh: -88, shin: -88, foot: 0),
    muscles: [Muscle.abs],
    anchor: Anchor.hip,
  ),
  'hanging_leg_raise': Motion(
    Pose(upper: -90, fore: -90, thigh: 95, shin: 95),
    Pose(upper: -90, fore: -90, thigh: 0, shin: 5, foot: -80),
    muscles: [Muscle.abs],
    anchor: Anchor.hand,
    floor: false,
    barAtHand: true,
  ),
  'cable_crunch': Motion(
    Pose(torso: -80, upper: 10, fore: 225, thigh: 90, shin: 180, foot: 180),
    Pose(torso: 10, upper: 100, fore: 315, thigh: 90, shin: 180, foot: 180),
    muscles: [Muscle.abs],
    cable: Offset(40, -150),
  ),
  'plank': Motion(
    Pose(torso: -13, upper: 90, fore: 0, thigh: 167, shin: 167, foot: 100),
    Pose(torso: -15, upper: 92, fore: 0, thigh: 166, shin: 166, foot: 100),
    muscles: [Muscle.abs],
    anchor: Anchor.hand,
  ),

  // ---------- shoulders ----------
  'press': Motion(
    Pose(upper: 75, fore: -95),
    Pose(upper: -88, fore: -90),
    muscles: [Muscle.shoulders, Muscle.triceps],
    foreshorten: true,
  ),
  'lateral_raise': Motion(
    Pose(upper: 78, fore: 82, thigh: 86, shin: 90),
    Pose(upper: -5, fore: 0, thigh: 86, shin: 90),
    muscles: [Muscle.shoulders],
    front: true,
  ),
  'front_raise': Motion(Pose(upper: 88, fore: 88), Pose(upper: -5, fore: -5), muscles: [Muscle.shoulders]),
  'reverse_fly': Motion(
    Pose(torso: -20, thigh: 75, shin: 100),
    Pose(torso: -20, upper: -90, fore: -90, reach: 0.3, thigh: 75, shin: 100),
    muscles: [Muscle.shoulders, Muscle.back],
    foreshorten: true,
  ),
  'face_pull': Motion(
    Pose(upper: 0, fore: 0),
    Pose(upper: 180, fore: -20, reach: 0.75),
    muscles: [Muscle.shoulders, Muscle.back],
    cable: Offset(110, -62),
  ),

  // ---------- added with the full library ----------
  'pullover': Motion(
    Pose(torso: 180, upper: 190, fore: 192, thigh: -20, shin: 95),
    Pose(torso: 180, upper: 272, fore: 272, thigh: -20, shin: 95),
    muscles: [Muscle.back, Muscle.chest],
    anchor: Anchor.hip,
    blocks: [Block(-60, 12, 8)],
  ),
  'incline_curl': Motion(
    Pose(torso: -125, upper: 100, fore: 100, thigh: 5, shin: 92),
    Pose(torso: -125, upper: 100, fore: -50, thigh: 5, shin: 92),
    muscles: [Muscle.biceps],
    anchor: Anchor.hip,
    blocks: [Block(-16, 16, 7)],
    pads: [Pad(Offset(-7, 6), Offset(-37, -36), width: 7)],
  ),
  'spider_curl': Motion(
    Pose(torso: -40, upper: 90, fore: 90, thigh: 70, shin: 100),
    Pose(torso: -40, upper: 90, fore: -80, thigh: 70, shin: 100),
    muscles: [Muscle.biceps],
    pads: [Pad(Offset(6, 7), Offset(44, -25), width: 7)],
  ),
  'high_cable_curl': Motion(
    Pose(upper: -2, fore: -2, thigh: 86, shin: 90),
    Pose(upper: -2, fore: -95, thigh: 86, shin: 90),
    muscles: [Muscle.biceps],
    front: true,
    cable: Offset(92, -58),
  ),
  'kickback': Motion(
    Pose(torso: -25, upper: 175, fore: 95, thigh: 75, shin: 100),
    Pose(torso: -25, upper: 175, fore: 178, thigh: 75, shin: 100),
    muscles: [Muscle.triceps],
  ),
  'wrist_curl': Motion(
    Pose(torso: -35, upper: 135, fore: 0, wrist: 60, thigh: 0, shin: 92),
    Pose(torso: -35, upper: 135, fore: 0, wrist: -40, thigh: 0, shin: 92),
    muscles: [Muscle.forearms],
    anchor: Anchor.hip,
    blocks: [Block(-16, 16, 7)],
  ),
  'reverse_wrist_curl': Motion(
    Pose(torso: -35, upper: 135, fore: 0, wrist: 55, thigh: 0, shin: 92),
    Pose(torso: -35, upper: 135, fore: 0, wrist: -30, thigh: 0, shin: 92),
    muscles: [Muscle.forearms],
    anchor: Anchor.hip,
    blocks: [Block(-16, 16, 7)],
  ),
  'wrist_roller': Motion(
    Pose(upper: 0, fore: 0, wrist: 50),
    Pose(upper: 0, fore: 0, wrist: -35),
    muscles: [Muscle.forearms, Muscle.shoulders],
  ),
  'farmer_walk': Motion(
    Pose(thigh: 75, shin: 95, thigh2: 105, shin2: 100),
    Pose(thigh: 105, shin: 100, thigh2: 75, shin2: 95),
    muscles: [Muscle.forearms, Muscle.shoulders],
    anchor: Anchor.hip,
  ),
  'dead_hang': Motion(
    Pose(upper: -90, fore: -90, thigh: 92, shin: 108),
    Pose(upper: -90, fore: -90, thigh: 97, shin: 100),
    muscles: [Muscle.forearms, Muscle.back],
    anchor: Anchor.hand,
    floor: false,
    barAtHand: true,
  ),
  'hip_thrust': Motion(
    Pose(torso: -150, upper: 30, fore: 30, thigh: -45, shin: 85),
    // -180, not 180: angles mix in a straight line, and -150 → 180 would spin the long way.
    Pose(torso: -180, upper: 0, fore: 0, thigh: 0, shin: 90),
    muscles: [Muscle.glutes, Muscle.hamstrings],
    blocks: [Block(-76, -38, -18)],
  ),
  'mountain_climber': Motion(
    Pose(torso: -23.6, thigh: 156.4, shin: 156.4, foot: 100),
    Pose(torso: -23.6, thigh: 60, shin: 140, foot: 100, thigh2: 156.4, shin2: 156.4),
    muscles: [Muscle.abs],
    anchor: Anchor.hand,
  ),
  'ab_wheel': Motion(
    Pose(torso: -15, thigh: 70, shin: 180, foot: 180),
    Pose(torso: -8, upper: 32, fore: 32, thigh: 150, shin: 180, foot: 180),
    muscles: [Muscle.abs],
    wheel: true,
  ),
  'upright_row': Motion(
    Pose(upper: 95, fore: 92, thigh: 86, shin: 90),
    Pose(upper: -25, fore: 175, thigh: 86, shin: 90),
    muscles: [Muscle.shoulders],
    front: true,
  ),

  // Just standing, for an exercise without a motion of its own.
  'none': Motion(Pose(), Pose(), muscles: []),
};

// ---------- the figure ----------

const _neck = 7.0, _headRadius = 8.5, _torso = 50.0, _upperArm = 27.0, _forearm = 25.0;
const _thigh = 36.0, _shin = 34.0, _foot = 11.0, _hand = 8.0;

Offset _dir(double degrees) {
  final r = degrees * math.pi / 180;
  return Offset(math.cos(r), math.sin(r));
}

class Arm {
  const Arm(this.shoulder, this.elbow, this.hand, this.grip);
  final Offset shoulder, elbow, hand; // hand: the wrist
  final Offset grip; // where the weight is held: the end of a bent hand, or the wrist
  Arm shift(Offset by) => Arm(shoulder + by, elbow + by, hand + by, grip + by);
}

class Leg {
  const Leg(this.hip, this.knee, this.ankle, this.toe);
  final Offset hip, knee, ankle, toe;
  Leg shift(Offset by) => Leg(hip + by, knee + by, ankle + by, toe + by);
}

/// Where every joint is at one moment.
class Figure {
  const Figure._(this.hip, this.shoulder, this.head, this.torsoAngle, this.arms, this.legs);

  final Offset hip;
  final Offset shoulder;
  final Offset head;
  final double torsoAngle;
  final List<Arm> arms; // near, far
  final List<Leg> legs; // near, far

  Figure _shift(Offset by) => Figure._(
    hip + by,
    shoulder + by,
    head + by,
    torsoAngle,
    [for (final a in arms) a.shift(by)],
    [for (final l in legs) l.shift(by)],
  );

  Offset get hand => arms.first.hand;

  Iterable<Offset> get points sync* {
    yield* [hip, shoulder, head];
    for (final a in arms) {
      yield* [a.elbow, a.hand, a.grip];
    }
    for (final l in legs) {
      yield* [l.knee, l.ankle, l.toe];
    }
  }

  /// The figure of [motion] at [progress] (0 = start pose, 1 = end pose), with its anchor
  /// where it is in the start pose.
  factory Figure.of(Motion motion, double progress) {
    final raw = _pose(motion, progress);
    if (progress == 0) return raw;
    return raw._shift(_anchor(motion, _pose(motion, 0)) - _anchor(motion, raw));
  }

  static Offset _anchor(Motion motion, Figure f) => switch (motion.anchor) {
    Anchor.hip => f.hip,
    Anchor.foot => f.legs.first.ankle,
    Anchor.toe => f.legs.first.toe,
    Anchor.hand => f.arms.first.hand,
  };

  static Figure _pose(Motion m, double t) {
    final a = m.start, b = m.end;
    double mix(double x, double y) => x + (y - x) * t;
    // The far limb: as given, or like the near one (side view) or mirrored (front view).
    double far(double near, double? given) => given ?? (m.front ? 180 - near : near);

    final torso = mix(a.torso, b.torso);
    final up = _dir(torso);
    const hip = Offset.zero;
    final shoulder = hip + up * _torso;
    final head = shoulder + up * (_neck + _headRadius);
    final across = _dir(torso + 90); // to the figure's right, seen from the front

    Arm arm(int side) {
      final ua = side > 0 ? a.upper : far(a.upper, a.upper2);
      final ub = side > 0 ? b.upper : far(b.upper, b.upper2);
      final fa = side > 0 ? a.fore : far(a.fore, a.fore2);
      final fb = side > 0 ? b.fore : far(b.fore, b.fore2);
      final s = shoulder + (m.front ? across * (13.0 * side) : Offset.zero);
      final Offset upper, fore;
      if (m.foreshorten) {
        upper = Offset.lerp(_dir(ua) * _upperArm * a.reach, _dir(ub) * _upperArm * b.reach, t)!;
        fore = Offset.lerp(_dir(fa) * _forearm * a.reach, _dir(fb) * _forearm * b.reach, t)!;
      } else {
        final reach = mix(a.reach, b.reach);
        upper = _dir(mix(ua, ub)) * _upperArm * reach;
        fore = _dir(mix(fa, fb)) * _forearm * reach;
      }
      final hand = s + upper + fore;
      final wa = a.wrist, wb = b.wrist;
      final grip = wa == null && wb == null ? hand : hand + _dir(mix(wa ?? fa, wb ?? fb)) * _hand;
      return Arm(s, s + upper, hand, grip);
    }

    Leg leg(int side) {
      double angle(double near, double? given, double near2, double? given2) =>
          side > 0 ? mix(near, near2) : mix(far(near, given), far(near2, given2));
      final h = hip + (m.front ? across * (8.0 * side) : Offset.zero);
      final knee = h + _dir(angle(a.thigh, a.thigh2, b.thigh, b.thigh2)) * _thigh;
      final ankle = knee + _dir(angle(a.shin, a.shin2, b.shin, b.shin2)) * _shin;
      final toe = ankle + _dir(angle(a.foot, a.foot2, b.foot, b.foot2)) * (m.front ? 7 : _foot);
      return Leg(h, knee, ankle, toe);
    }

    return Figure._(hip, shoulder, head, torso, [arm(1), arm(-1)], [leg(1), leg(-1)]);
  }
}

/// How far into the lift the loop is, from 0 (start pose) to 1 (end pose): a pause, the
/// lift, a pause at the top, then a slower way back.
double liftProgress(double loop) {
  final t = loop - loop.floorToDouble();
  if (t < 0.12) return 0;
  if (t < 0.45) return Curves.easeInOutCubic.transform((t - 0.12) / 0.33);
  if (t < 0.6) return 1;
  if (t < 0.95) return 1 - Curves.easeInOutCubic.transform((t - 0.6) / 0.35);
  return 0;
}

/// Everything a motion can occupy over the whole loop, and where the floor is.
class _Frame {
  _Frame(this.bounds, this.floor);
  final Rect bounds;
  final double? floor;
}

final _frames = <Motion, _Frame>{};

_Frame _frameOf(Motion m) => _frames.putIfAbsent(m, () {
  final points = <Offset>[];
  double floor = double.negativeInfinity;
  for (var i = 0; i <= 8; i++) {
    final f = Figure.of(m, i / 8);
    points.addAll(f.points);
    for (final l in f.legs) {
      floor = [floor, l.ankle.dy + 4, l.toe.dy + 3, l.knee.dy + 6].reduce(math.max);
    }
    for (final a in f.arms) {
      floor = [floor, a.hand.dy + 3, a.elbow.dy + 4].reduce(math.max);
    }
    floor = [floor, f.hip.dy + 8, f.shoulder.dy + 8].reduce(math.max);
  }
  final start = Figure.of(m, 0);
  if (m.cable != null) points.addAll([m.cable!, Offset(-m.cable!.dx, m.cable!.dy)].take(m.front ? 2 : 1));
  for (final p in m.pads) {
    points.addAll([p.a, p.b]);
  }
  for (final b in m.blocks) {
    points.addAll([Offset(b.left, b.top), Offset(b.right, b.top)]);
  }
  if (m.barAtHand) points.addAll([start.hand.translate(-22, 0), start.hand.translate(22, 0)]);
  var bounds = Rect.fromPoints(points.first, points.first);
  for (final p in points) {
    bounds = bounds.expandToInclude(Rect.fromCenter(center: p, width: 24, height: 24));
  }
  if (m.floor) bounds = bounds.expandToInclude(Rect.fromLTWH(bounds.left, floor, 1, 1));
  return _Frame(bounds, m.floor ? floor : null);
});

// ---------- painting ----------

const _near = Color(0xFF4D4D4D);
const _far = Color(0xFF2B2B2B);
const _steel = Color(0xFF7A7A7A);

class ExerciseFigurePainter extends CustomPainter {
  /// Paints [motion] at [loop] (seconds into the loop / its length). With [still] it
  /// shows the end pose, where the muscles work hardest.
  ExerciseFigurePainter({required this.motion, required this.equipment, this.loop, this.still = false})
    : super(repaint: loop);

  final Motion motion;
  final String equipment; // barbell, dumbbell, cable, machine or bodyweight
  final Animation<double>? loop;
  final bool still;

  /// The design is drawn about this tall, whatever the motion.
  static const designHeight = 185.0;

  @override
  void paint(Canvas canvas, Size size) {
    final m = motion;
    final progress = still ? 1.0 : liftProgress(loop?.value ?? 0);
    final glow = 0.25 + 0.75 * progress;
    final frame = _frameOf(m);
    final f = Figure.of(m, progress);
    final start = Figure.of(m, 0);

    final bounds = frame.bounds;
    // The same size for every exercise, unless one would not fit (a pull-up is tall).
    final scale = math.min(size.height / math.max(designHeight, bounds.height), size.width / (bounds.width + 20));
    canvas
      ..save()
      ..translate(size.width / 2, size.height / 2)
      ..scale(scale)
      ..translate(-bounds.center.dx, -bounds.center.dy);

    final floor = frame.floor;
    if (floor != null) {
      final from = Offset(bounds.left - 30, floor), to = Offset(bounds.right + 30, floor);
      canvas.drawLine(
        from,
        to,
        Paint()
          ..strokeWidth = 1.2
          ..shader = const LinearGradient(colors: [Color(0x00FFFFFF), Color(0x33FFFFFF), Color(0x00FFFFFF)])
              .createShader(Rect.fromPoints(from, to.translate(0, 1))),
      );
    }

    // Benches, seats and pads.
    for (final b in m.blocks) {
      final bottom = floor ?? b.top + 20;
      canvas.drawRRect(
        RRect.fromLTRBR(b.left, b.top, b.right, bottom, const Radius.circular(3)),
        Paint()..color = const Color(0xFF1E1E1E),
      );
      canvas.drawLine(
        Offset(b.left + 2, b.top),
        Offset(b.right - 2, b.top),
        Paint()
          ..color = const Color(0xFF333333)
          ..strokeWidth = 1.5,
      );
    }
    for (final p in m.pads) {
      canvas.drawLine(p.a, p.b, _stroke(const Color(0xFF262626), p.width));
    }
    if (m.barAtHand) {
      canvas.drawLine(start.hand.translate(-22, 0), start.hand.translate(22, 0), _stroke(const Color(0xFF5E5E5E), 3));
    }

    // Cables, from the pulley to the hand.
    final cable = m.cable;
    if (cable != null) {
      final ends = [(cable, f.arms[0].hand), if (m.front) (Offset(-cable.dx, cable.dy), f.arms[1].hand)];
      for (final (pulley, hand) in ends) {
        canvas.drawLine(pulley, hand, _stroke(const Color(0xFF555555), 1));
        canvas.drawCircle(pulley, 3.5, _stroke(const Color(0xFF555555), 1.2));
      }
    }

    // The figure: far limbs first, then the body, then the near limbs.
    _leg(canvas, f.legs[1], m.front ? _near : _far);
    _arm(canvas, f.arms[1], m.front ? _near : _far);
    _leg(canvas, f.legs[0], _near);
    if (m.footPlate) {
      final l = f.legs[0];
      final along = _unit(l.toe - l.ankle);
      final under = Offset(-along.dy, along.dx) * -6; // under the sole
      canvas.drawLine(l.ankle - along * 8 + under, l.toe + along * 10 + under, _stroke(const Color(0xFF3A3A3A), 5));
    }
    if (m.front) {
      final across = _dir(f.torsoAngle + 90);
      canvas.drawLine(f.hip, f.shoulder, _stroke(_near, 20));
      canvas.drawLine(f.shoulder - across * 13, f.shoulder + across * 13, _stroke(_near, 9));
      canvas.drawLine(f.hip - across * 8, f.hip + across * 8, _stroke(_near, 11));
    } else {
      canvas.drawLine(f.hip, f.shoulder, _stroke(_near, 15));
    }
    final up = _dir(f.torsoAngle);
    canvas.drawLine(f.shoulder, f.shoulder + up * _neck, _stroke(_near, 6));
    canvas.drawCircle(f.head, _headRadius, Paint()..color = _near);
    _arm(canvas, f.arms[0], _near);

    if (m.roller != Roller.none) {
      final l = f.legs[0];
      final d = _unit(l.ankle - l.knee);
      final front = Offset(d.dy, -d.dx); // limbs: the front is this side
      final side = m.roller == Roller.front ? 1.0 : -1.0;
      canvas.drawCircle(l.ankle - d * 4 + front * (9 * side), 6, Paint()..color = const Color(0xFF3A3A3A));
    }

    for (final muscle in m.muscles) {
      _muscle(canvas, f, muscle, glow);
    }

    // What the hands hold.
    if (m.wheel) _plate(canvas, f.arms[0].grip.translate(0, 4), 7);
    final hands = [f.arms[0].grip, if (m.front) f.arms[1].grip];
    if (m.front && equipment == 'barbell') {
      // Seen from the front, a barbell is a bar across both hands.
      final l = f.arms[1].grip, r = f.arms[0].grip;
      final along = _unit(r - l);
      canvas.drawLine(l - along * 22, r + along * 22, _stroke(_steel, 2.5));
      for (final end in [l - along * 20, r + along * 20]) {
        canvas.drawLine(end - const Offset(0, 9), end + const Offset(0, 9), _stroke(_steel, 4));
      }
    }
    for (final hand in hands) {
      switch (equipment) {
        case 'barbell':
          if (m.front) break;
          _plate(canvas, hand, 10.5);
        case 'dumbbell' || 'kettlebell':
          _plate(canvas, hand, 5.5);
        case 'cable':
          canvas.drawCircle(hand, 2.6, Paint()..color = _steel);
      }
    }
    canvas.restore();
  }

  void _arm(Canvas canvas, Arm a, Color color) {
    canvas.drawLine(a.shoulder, a.elbow, _stroke(color, 9));
    canvas.drawLine(a.elbow, a.hand, _stroke(color, 7.5));
    if (a.grip != a.hand) canvas.drawLine(a.hand, a.grip, _stroke(color, 6));
  }

  void _leg(Canvas canvas, Leg l, Color color) {
    canvas.drawLine(l.hip, l.knee, _stroke(color, 12));
    canvas.drawLine(l.knee, l.ankle, _stroke(color, 9));
    canvas.drawLine(l.ankle, l.toe, _stroke(color, 6));
  }

  void _plate(Canvas canvas, Offset at, double radius) {
    canvas.drawCircle(at, radius, Paint()..color = const Color(0xFF1A1A1A));
    canvas.drawCircle(at, radius, _stroke(_steel, radius > 8 ? 2.2 : 1.6));
    canvas.drawCircle(at, radius > 8 ? 2.2 : 1.5, Paint()..color = _steel);
  }

  /// Lights up one muscle. [glow] runs from 0.25 (relaxed) to 1 (fully contracted).
  void _muscle(Canvas canvas, Figure f, Muscle muscle, double glow) {
    final m = motion;
    final arms = m.front ? f.arms : [f.arms[0]];
    final legs = m.front ? f.legs : [f.legs[0]];
    // On the torso and on the limbs, which side is "front" (+1) or "back" (-1). Seen from
    // the front, muscles sit in the middle (0).
    double side(double s) => m.front ? 0 : s;
    switch (muscle) {
      case Muscle.chest when m.front:
        final across = _dir(f.torsoAngle + 90), down = -_dir(f.torsoAngle);
        for (final s in [-1.0, 1.0]) {
          _spot(canvas, f.shoulder + across * (6 * s) + down * 9, 6.5, glow);
        }
      case Muscle.chest:
        _band(canvas, f.hip, f.shoulder, 15, 0.58, 0.92, side(1), true, glow);
      case Muscle.back:
        _band(canvas, f.hip, f.shoulder, 15, 0.42, 0.92, side(-1), true, glow);
      case Muscle.lowerBack:
        _band(canvas, f.hip, f.shoulder, 15, 0.06, 0.42, side(-1), true, glow);
      case Muscle.abs:
        _band(canvas, f.hip, f.shoulder, m.front ? 14 : 15, 0.1, 0.52, side(1), true, glow);
      case Muscle.shoulders:
        for (final a in arms) {
          _spot(canvas, a.shoulder, 6.5, glow);
        }
      case Muscle.biceps:
        for (final a in arms) {
          _band(canvas, a.shoulder, a.elbow, 9, 0.22, 0.86, side(1), false, glow);
        }
      case Muscle.triceps:
        for (final a in arms) {
          _band(canvas, a.shoulder, a.elbow, 9, 0.18, 0.86, side(-1), false, glow);
        }
      case Muscle.forearms:
        for (final a in arms) {
          _band(canvas, a.elbow, a.hand, 7.5, 0.1, 0.75, 0, false, glow);
        }
      case Muscle.quads:
        for (final l in legs) {
          _band(canvas, l.hip, l.knee, 12, 0.18, 0.86, side(1), false, glow);
        }
      case Muscle.hamstrings:
        for (final l in legs) {
          _band(canvas, l.hip, l.knee, 12, 0.2, 0.86, side(-1), false, glow);
        }
      case Muscle.glutes:
        final d = _unit(f.shoulder - f.hip);
        _spot(canvas, f.hip + Offset(d.dy, -d.dx) * 5, 7, glow);
      case Muscle.calves:
        for (final l in legs) {
          _band(canvas, l.knee, l.ankle, 9, 0.1, 0.55, side(-1), false, glow);
        }
    }
  }

  /// A glowing strip along part of a body segment, from [from] to [to] of its length,
  /// pushed to its front ([side] 1) or back (-1).
  void _band(Canvas c, Offset a, Offset b, double width, double from, double to, double side, bool torso, double glow) {
    final d = _unit(b - a);
    final length = (b - a).distance;
    // The torso runs up from the hip, the limbs away from the body, so their fronts are on
    // opposite turns of the direction.
    final front = torso ? Offset(-d.dy, d.dx) : Offset(d.dy, -d.dx);
    final shift = front * (side * width * 0.28);
    final p0 = a + d * (length * from) + shift, p1 = a + d * (length * to) + shift;
    c.drawLine(
      p0,
      p1,
      _stroke(Colors.white.withValues(alpha: 0.5 * glow), width * 0.95)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
    );
    c.drawLine(p0, p1, _stroke(Colors.white.withValues(alpha: 0.35 + 0.65 * glow), width * 0.5));
  }

  void _spot(Canvas c, Offset at, double radius, double glow) {
    c.drawCircle(
      at,
      radius,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.5 * glow)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
    );
    c.drawCircle(at, radius * 0.55, Paint()..color = Colors.white.withValues(alpha: 0.35 + 0.65 * glow));
  }

  static Paint _stroke(Color color, double width) => Paint()
    ..color = color
    ..style = PaintingStyle.stroke
    ..strokeWidth = width
    ..strokeCap = StrokeCap.round;

  static Offset _unit(Offset o) => o.distance == 0 ? const Offset(1, 0) : o / o.distance;

  @override
  bool shouldRepaint(ExerciseFigurePainter old) =>
      old.motion != motion || old.equipment != equipment || old.still != still || old.loop != loop;
}

/// The looping clip for an exercise. With [still], or when the phone asks for less
/// motion, it shows the end pose instead.
class ExerciseAnimation extends StatefulWidget {
  const ExerciseAnimation({super.key, required this.motion, required this.equipment, this.still = false});

  final String motion;
  final String equipment;
  final bool still;

  /// How long one repetition takes, pauses included.
  static const loop = Duration(milliseconds: 3600);

  @override
  State<ExerciseAnimation> createState() => _ExerciseAnimationState();
}

class _ExerciseAnimationState extends State<ExerciseAnimation> with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(vsync: this, duration: ExerciseAnimation.loop);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final still = widget.still || MediaQuery.disableAnimationsOf(context);
    if (still) {
      _controller.stop();
    } else if (!_controller.isAnimating) {
      _controller.repeat();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final still = widget.still || MediaQuery.disableAnimationsOf(context);
    return RepaintBoundary(
      child: CustomPaint(
        size: Size.infinite,
        painter: ExerciseFigurePainter(
          motion: motions[widget.motion] ?? motions['none']!,
          equipment: widget.equipment,
          loop: still ? null : _controller,
          still: still,
        ),
      ),
    );
  }
}
