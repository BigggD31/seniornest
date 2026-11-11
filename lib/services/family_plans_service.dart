import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'push_service.dart';

/// Nov 7 2026: Family Plans (build 1.06) -- plans and polls on Home's second
/// tab. Everything is stored in the family_* tables (see the Supabase
/// migration family_plans_a_tables_and_rules). Who can see what is enforced
/// by the database itself (visible_to_ids + row-level security), so every
/// query below can simply ask for the nest's rows: hidden items never come
/// back for a hidden person.

class FamilyPlan {
  FamilyPlan({
    required this.id,
    required this.nestId,
    required this.authorId,
    required this.title,
    required this.details,
    required this.location,
    required this.startsAt,
    required this.sourceTz,
    required this.remind24h,
    required this.rsvpEnabled,
    this.hideRsvpNames = false,
    required this.visibleToIds,
    required this.canceledAt,
    required this.createdAt,
  });

  final String id;
  final String nestId;
  final String authorId;
  final String title;
  final String details;
  final String location;
  final DateTime startsAt; // local time on this phone
  final String sourceTz; // friendly label, e.g. "Eastern Time"
  final bool remind24h;
  final bool rsvpEnabled;

  /// Nov 11 2026: poster chose to show counts only. The database enforces
  /// it (other people's answers are not readable), like polls' hide_voters.
  final bool hideRsvpNames;
  final List<String> visibleToIds; // empty = everyone
  final DateTime? canceledAt;
  final DateTime createdAt;

  bool get isPrivate => visibleToIds.isNotEmpty;
  bool get isCanceled => canceledAt != null;

  /// Fades once start time + 3 hours has passed.
  bool get isPast =>
      DateTime.now().isAfter(startsAt.add(const Duration(hours: 3)));

  /// Hidden from the tab 30 days after it faded.
  bool get isExpired =>
      DateTime.now().isAfter(startsAt.add(const Duration(hours: 3, days: 30)));

  factory FamilyPlan.fromMap(Map<String, dynamic> m) {
    return FamilyPlan(
      id: m['id'] as String,
      nestId: m['nest_id'] as String,
      authorId: m['author_id'] as String,
      title: (m['title'] as String?) ?? '',
      details: (m['details'] as String?) ?? '',
      location: (m['location'] as String?) ?? '',
      startsAt: DateTime.parse(m['starts_at'] as String).toLocal(),
      sourceTz: (m['source_tz'] as String?) ?? '',
      remind24h: m['remind_24h'] as bool? ?? true,
      rsvpEnabled: m['rsvp_enabled'] as bool? ?? false,
      hideRsvpNames: m['hide_rsvp_names'] as bool? ?? false,
      visibleToIds: _stringList(m['visible_to_ids']),
      canceledAt: m['canceled_at'] == null
          ? null
          : DateTime.parse(m['canceled_at'] as String).toLocal(),
      createdAt: DateTime.parse(m['created_at'] as String).toLocal(),
    );
  }
}

class FamilyPoll {
  FamilyPoll({
    required this.id,
    required this.nestId,
    required this.authorId,
    required this.question,
    required this.options,
    required this.closesAt,
    required this.closedEarlyAt,
    required this.visibleToIds,
    required this.createdAt,
    this.hideVoters = false,
  });

  final String id;
  final String nestId;
  final String authorId;
  final String question;
  final List<String> options;
  final DateTime closesAt;
  final DateTime? closedEarlyAt;
  final List<String> visibleToIds;
  final DateTime createdAt;

  /// Nov 8 2026: the creator chose not to show who voted for what. The
  /// database then only lets each person read their own vote.
  final bool hideVoters;

  bool get isPrivate => visibleToIds.isNotEmpty;
  bool get isClosed =>
      closedEarlyAt != null || !closesAt.isAfter(DateTime.now());

  factory FamilyPoll.fromMap(Map<String, dynamic> m) {
    final rawOptions = m['options'];
    final options = rawOptions is List
        ? rawOptions.map((o) => o.toString()).toList()
        : <String>[];
    return FamilyPoll(
      id: m['id'] as String,
      nestId: m['nest_id'] as String,
      authorId: m['author_id'] as String,
      question: (m['question'] as String?) ?? '',
      options: options,
      closesAt: DateTime.parse(m['closes_at'] as String).toLocal(),
      closedEarlyAt: m['closed_early_at'] == null
          ? null
          : DateTime.parse(m['closed_early_at'] as String).toLocal(),
      visibleToIds: _stringList(m['visible_to_ids']),
      createdAt: DateTime.parse(m['created_at'] as String).toLocal(),
      hideVoters: m['hide_voters'] == true,
    );
  }
}

class FamilyComment {
  FamilyComment({
    required this.id,
    required this.userId,
    required this.body,
    required this.createdAt,
  });
  final String id;
  final String userId;
  final String body;
  final DateTime createdAt;
}

/// Everything the Family Plans tab needs for one nest, loaded together.
class FamilyPlansData {
  FamilyPlansData({
    required this.plans,
    required this.polls,
    required this.votes,
    required this.rsvps,
    required this.hearts,
    required this.commentCounts,
    required this.names,
    this.hiddenCounts = const {},
    this.rsvpCounts = const {},
  });

  final List<FamilyPlan> plans;
  final List<FamilyPoll> polls;

  /// pollId -> (userId -> option index)
  final Map<String, Map<String, int>> votes;

  /// planId -> (userId -> 'going' | 'maybe' | 'cant')
  final Map<String, Map<String, String>> rsvps;

  /// "plan:<id>" / "poll:<id>" -> user ids who hearted it
  final Map<String, Set<String>> hearts;

  /// "plan:<id>" / "poll:<id>" -> number of comments
  final Map<String, int> commentCounts;

  /// userId -> first name to show
  final Map<String, String> names;

  /// pollId -> votes per option, only for polls whose voters are hidden
  /// (the database gives those as counts, never as individual votes).
  final Map<String, List<int>> hiddenCounts;

  /// planId -> [going, maybe, cant], only for plans that hide names.
  final Map<String, List<int>> rsvpCounts;

  static FamilyPlansData empty() => FamilyPlansData(
        plans: [],
        polls: [],
        votes: {},
        rsvps: {},
        hearts: {},
        commentCounts: {},
        names: {},
      );
}

List<String> _stringList(dynamic v) {
  if (v is List) return v.map((e) => e.toString()).toList();
  return <String>[];
}

class FamilyPlansService {
  FamilyPlansService._();

  static SupabaseClient get _db => Supabase.instance.client;
  static String? get myId => _db.auth.currentUser?.id;

  static String key(String type, String id) => '$type:$id';

  // ── Time zone label ────────────────────────────────────────────
  // The phone does not tell us an IANA zone name without an extra package,
  // so the label is built from the phone's own zone abbreviation. The
  // plan's start time itself is stored as one exact moment (UTC), so every
  // phone shows it correctly in its own zone either way; the label is only
  // for the "Planned in Eastern Time" line.
  static String zoneLabel([DateTime? at]) {
    final now = at ?? DateTime.now();
    switch (now.timeZoneName) {
      case 'EST':
      case 'EDT':
        return 'Eastern Time';
      case 'CST':
      case 'CDT':
        return 'Central Time';
      case 'MST':
      case 'MDT':
        return 'Mountain Time';
      case 'PST':
      case 'PDT':
        return 'Pacific Time';
      case 'AKST':
      case 'AKDT':
        return 'Alaska Time';
      case 'HST':
      case 'HDT':
        return 'Hawaii Time';
    }
    final off = now.timeZoneOffset;
    final sign = off.isNegative ? '-' : '+';
    final abs = off.abs();
    final h = abs.inHours;
    final m = abs.inMinutes.remainder(60);
    final mm = m == 0 ? '' : ':${m.toString().padLeft(2, '0')}';
    return 'GMT$sign$h$mm';
  }

  // ── Loading ────────────────────────────────────────────────────

  static Future<FamilyPlansData> load(String nestId) async {
    if (nestId.isEmpty) return FamilyPlansData.empty();

    final planRows = await _db
        .from('family_plans')
        .select()
        .eq('nest_id', nestId)
        .order('starts_at', ascending: true);
    final pollRows = await _db
        .from('family_polls')
        .select()
        .eq('nest_id', nestId)
        .order('created_at', ascending: false);

    final plans = (planRows as List)
        .map((r) => FamilyPlan.fromMap(Map<String, dynamic>.from(r as Map)))
        .where((p) => !p.isExpired)
        .toList();
    final polls = (pollRows as List)
        .map((r) => FamilyPoll.fromMap(Map<String, dynamic>.from(r as Map)))
        .toList();

    final planIds = plans.map((p) => p.id).toList();
    final pollIds = polls.map((p) => p.id).toList();

    final votes = <String, Map<String, int>>{};
    final rsvps = <String, Map<String, String>>{};
    final hearts = <String, Set<String>>{};
    final commentCounts = <String, int>{};
    final hiddenCounts = <String, List<int>>{};
    final rsvpCounts = <String, List<int>>{};
    final userIds = <String>{
      for (final p in plans) p.authorId,
      for (final p in polls) p.authorId,
    };

    if (pollIds.isNotEmpty) {
      try {
        final rows =
            await _db.from('poll_votes').select().inFilter('poll_id', pollIds);
        for (final r in rows as List) {
          final pid = r['poll_id'] as String;
          final uid = r['user_id'] as String;
          (votes[pid] ??= {})[uid] = (r['option_index'] as num).toInt();
        }
      } catch (e) {
        debugPrint('FAMILY_PLANS votes load error: $e');
      }
      for (final m in votes.values) {
        userIds.addAll(m.keys);
      }
      for (final p in polls.where((p) => p.hideVoters)) {
        try {
          final rows = await _db
              .rpc('poll_option_counts', params: {'p_poll_id': p.id});
          final counts = List<int>.filled(p.options.length, 0);
          for (final r in rows as List) {
            final i = (r['option_index'] as num).toInt();
            if (i >= 0 && i < counts.length) {
              counts[i] = (r['votes'] as num).toInt();
            }
          }
          hiddenCounts[p.id] = counts;
        } catch (e) {
          debugPrint('FAMILY_PLANS hidden counts error: $e');
        }
      }
    }
    if (planIds.isNotEmpty) {
      try {
        final rows =
            await _db.from('plan_rsvps').select().inFilter('plan_id', planIds);
        for (final r in rows as List) {
          final pid = r['plan_id'] as String;
          final uid = r['user_id'] as String;
          (rsvps[pid] ??= {})[uid] = r['status'] as String;
          userIds.add(uid);
        }
      } catch (e) {
        debugPrint('FAMILY_PLANS rsvps load error: $e');
      }
      for (final p in plans.where((p) => p.hideRsvpNames)) {
        try {
          final rows =
              await _db.rpc('plan_rsvp_counts', params: {'p_plan_id': p.id});
          final r = (rows as List).isEmpty ? null : rows.first as Map;
          if (r != null) {
            rsvpCounts[p.id] = [
              (r['going'] as num).toInt(),
              (r['maybe'] as num).toInt(),
              (r['cant'] as num).toInt(),
            ];
          }
        } catch (e) {
          debugPrint('FAMILY_PLANS rsvp counts error: $e');
        }
      }
    }
    final allItemIds = [...planIds, ...pollIds];
    if (allItemIds.isNotEmpty) {
      try {
        final rows = await _db
            .from('family_item_hearts')
            .select()
            .inFilter('item_id', allItemIds);
        for (final r in rows as List) {
          final k = key(r['item_type'] as String, r['item_id'] as String);
          (hearts[k] ??= <String>{}).add(r['user_id'] as String);
        }
      } catch (e) {
        debugPrint('FAMILY_PLANS hearts load error: $e');
      }
      try {
        final rows = await _db
            .from('family_item_comments')
            .select('item_type, item_id')
            .inFilter('item_id', allItemIds);
        for (final r in rows as List) {
          final k = key(r['item_type'] as String, r['item_id'] as String);
          commentCounts[k] = (commentCounts[k] ?? 0) + 1;
        }
      } catch (e) {
        debugPrint('FAMILY_PLANS comments load error: $e');
      }
    }

    final me = myId;
    if (me != null) userIds.add(me);
    final names = await _namesFor(userIds);
    return FamilyPlansData(
      plans: plans,
      polls: polls,
      votes: votes,
      rsvps: rsvps,
      hearts: hearts,
      commentCounts: commentCounts,
      names: names,
      hiddenCounts: hiddenCounts,
      rsvpCounts: rsvpCounts,
    );
  }

  /// Profile pictures by user id, filled in whenever names are loaded, so
  /// "Posted by" and comments can show the same avatar as the rest of the app.
  static final Map<String, String> avatarUrls = {};

  static Future<Map<String, String>> _namesFor(Set<String> ids) async {
    final out = <String, String>{};
    if (ids.isEmpty) return out;
    try {
      final rows = await _db
          .from('user_profiles')
          .select('id, display_name, preferred_name, avatar_url')
          .inFilter('id', ids.toList());
      for (final r in rows as List) {
        avatarUrls[r['id'] as String] = (r['avatar_url'] as String?) ?? '';
        final preferred = ((r['preferred_name'] as String?) ?? '').trim();
        final display = ((r['display_name'] as String?) ?? '').trim();
        final n = preferred.isNotEmpty ? preferred : display;
        if (n.isNotEmpty) out[r['id'] as String] = n;
      }
    } catch (e) {
      debugPrint('FAMILY_PLANS names load error: $e');
    }
    return out;
  }

  /// Names for a set of user ids (used by the comments sheet).
  static Future<Map<String, String>> namesFor(Iterable<String> ids) =>
      _namesFor(ids.toSet());

  static Future<String> _myName() async {
    final uid = myId;
    if (uid == null) return 'Someone';
    final n = await _namesFor({uid});
    return n[uid] ?? 'Someone';
  }

  // ── Plans ──────────────────────────────────────────────────────

  static Future<void> createPlan({
    required String nestId,
    required String title,
    required String details,
    required String location,
    required DateTime startsAt,
    required bool remind24h,
    required bool rsvpEnabled,
    bool hideRsvpNames = false,
    required List<String> visibleToIds,
  }) async {
    final uid = myId;
    if (uid == null) throw StateError('Not signed in');
    // Poster is always on a private list.
    final visible = visibleToIds.isEmpty
        ? null
        : ({...visibleToIds, uid}.toList());
    await _db.from('family_plans').insert({
      'nest_id': nestId,
      'author_id': uid,
      'title': title,
      'details': details.isEmpty ? null : details,
      'location': location.isEmpty ? null : location,
      'starts_at': startsAt.toUtc().toIso8601String(),
      'source_tz': zoneLabel(startsAt),
      'remind_24h': remind24h,
      'rsvp_enabled': rsvpEnabled,
      if (hideRsvpNames) 'hide_rsvp_names': true,
      'visible_to_ids': visible,
    });
    _pushToViewers(
      nestId: nestId,
      visibleToIds: visible ?? const [],
      title: 'New plan from ${await _myName()}',
      body: 'Open SeniorNest to see it.',
    );
  }

  static Future<void> updatePlan({
    required FamilyPlan plan,
    required String title,
    required String details,
    required String location,
    required DateTime startsAt,
    required bool remind24h,
    required bool rsvpEnabled,
    bool hideRsvpNames = false,
  }) async {
    final timeChanged = startsAt.toUtc() != plan.startsAt.toUtc();
    await _db.from('family_plans').update({
      'title': title,
      'details': details.isEmpty ? null : details,
      'location': location.isEmpty ? null : location,
      'starts_at': startsAt.toUtc().toIso8601String(),
      if (timeChanged) 'source_tz': zoneLabel(startsAt),
      'remind_24h': remind24h,
      'rsvp_enabled': rsvpEnabled,
      if (hideRsvpNames != plan.hideRsvpNames)
        'hide_rsvp_names': hideRsvpNames,
      // A new time means the 24-hour reminder should be sent fresh.
      if (timeChanged) 'reminder_sent_at': null,
    }).eq('id', plan.id);
    if (timeChanged) {
      _pushToViewers(
        nestId: plan.nestId,
        visibleToIds: plan.visibleToIds,
        title: 'Plan changed',
        body: '${await _myName()} changed a plan. Open SeniorNest to see it.',
      );
    }
  }

  static Future<void> cancelPlan(FamilyPlan plan) async {
    await _db.from('family_plans').update(
        {'canceled_at': DateTime.now().toUtc().toIso8601String()}).eq(
        'id', plan.id);
    _pushToViewers(
      nestId: plan.nestId,
      visibleToIds: plan.visibleToIds,
      title: 'Plan canceled',
      body: '${await _myName()} canceled a plan.',
    );
  }

  static Future<void> deletePlan(String id) async {
    await _db.from('family_plans').delete().eq('id', id);
  }

  static Future<void> setRsvp(String planId, String status) async {
    final uid = myId;
    if (uid == null) return;
    await _db.from('plan_rsvps').upsert({
      'plan_id': planId,
      'user_id': uid,
      'status': status,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }, onConflict: 'plan_id,user_id');
  }

  // ── Polls ──────────────────────────────────────────────────────

  static Future<void> createPoll({
    required String nestId,
    required String question,
    required List<String> options,
    required Duration closesIn,
    required List<String> visibleToIds,
    bool hideVoters = false,
  }) async {
    final uid = myId;
    if (uid == null) throw StateError('Not signed in');
    final visible = visibleToIds.isEmpty
        ? null
        : ({...visibleToIds, uid}.toList());
    await _db.from('family_polls').insert({
      'hide_voters': hideVoters,
      'nest_id': nestId,
      'author_id': uid,
      'question': question,
      'options': options,
      'closes_at': DateTime.now().add(closesIn).toUtc().toIso8601String(),
      'visible_to_ids': visible,
    });
    _pushToViewers(
      nestId: nestId,
      visibleToIds: visible ?? const [],
      title: 'New poll from ${await _myName()}',
      body: 'Open SeniorNest to vote.',
    );
  }

  static Future<void> closePollEarly(String id) async {
    await _db.from('family_polls').update(
        {'closed_early_at': DateTime.now().toUtc().toIso8601String()}).eq(
        'id', id);
  }

  static Future<void> deletePoll(String id) async {
    await _db.from('family_polls').delete().eq('id', id);
  }

  static Future<void> vote(String pollId, int optionIndex) async {
    final uid = myId;
    if (uid == null) return;
    await _db.from('poll_votes').upsert({
      'poll_id': pollId,
      'user_id': uid,
      'option_index': optionIndex,
      'voted_at': DateTime.now().toUtc().toIso8601String(),
    }, onConflict: 'poll_id,user_id');
  }

  // ── Hearts and comments (plans and polls) ──────────────────────

  static Future<void> setHeart(String type, String itemId, bool on) async {
    final uid = myId;
    if (uid == null) return;
    if (on) {
      await _db.from('family_item_hearts').upsert({
        'item_type': type,
        'item_id': itemId,
        'user_id': uid,
      }, onConflict: 'item_type,item_id,user_id');
      _pushToPoster(
        type: type,
        itemId: itemId,
        title: '${await _myName()} loved your ${type == 'poll' ? 'poll' : 'plan'}',
        body: 'Tap to see it in SeniorNest.',
      );
    } else {
      await _db
          .from('family_item_hearts')
          .delete()
          .eq('item_type', type)
          .eq('item_id', itemId)
          .eq('user_id', uid);
    }
  }

  static Future<List<FamilyComment>> loadComments(
      String type, String itemId) async {
    final rows = await _db
        .from('family_item_comments')
        .select()
        .eq('item_type', type)
        .eq('item_id', itemId)
        .order('created_at', ascending: true);
    return (rows as List)
        .map((r) => FamilyComment(
              id: r['id'] as String,
              userId: r['user_id'] as String,
              body: (r['body'] as String?) ?? '',
              createdAt: DateTime.parse(r['created_at'] as String).toLocal(),
            ))
        .toList();
  }

  static Future<void> addComment(String type, String itemId, String body) async {
    final uid = myId;
    if (uid == null) return;
    await _db.from('family_item_comments').insert({
      'item_type': type,
      'item_id': itemId,
      'user_id': uid,
      'body': body,
    });
    _pushToPoster(
      type: type,
      itemId: itemId,
      title: '${await _myName()} replied to your ${type == 'poll' ? 'poll' : 'plan'}',
      body: body.length > 80 ? '${body.substring(0, 80)}...' : body,
    );
  }

  static Future<void> deleteComment(String id) async {
    await _db.from('family_item_comments').delete().eq('id', id);
  }

  // ── Members (for the "Who can see this" picker) ────────────────

  /// Everyone in the nest except me: {id, name}. Placeholder sample people
  /// never come from here, only real members.
  static Future<List<Map<String, String>>> otherMembers(String nestId) async {
    final uid = myId;
    final rows = await _db
        .from('nest_members')
        .select(
            'user_id, user_profiles(display_name, preferred_name)')
        .eq('nest_id', nestId);
    final out = <Map<String, String>>[];
    for (final r in rows as List) {
      final id = r['user_id'] as String? ?? '';
      if (id.isEmpty || id == uid) continue;
      final p = r['user_profiles'] as Map?;
      final preferred = ((p?['preferred_name'] as String?) ?? '').trim();
      final display = ((p?['display_name'] as String?) ?? '').trim();
      final name = preferred.isNotEmpty ? preferred : display;
      if (name.isEmpty) continue;
      out.add({'id': id, 'name': name});
    }
    return out;
  }

  // ── Pushes ─────────────────────────────────────────────────────

  /// Nov 11 2026: push to ONLY the person who posted the plan or poll
  /// (never to me, never to anyone else). Used for hearts and replies.
  /// Fire-and-forget: a failed push must never fail the heart or reply.
  static Future<void> _pushToPoster({
    required String type,
    required String itemId,
    required String title,
    required String body,
  }) async {
    try {
      final uid = myId;
      final row = await _db
          .from(type == 'poll' ? 'family_polls' : 'family_plans')
          .select('author_id')
          .eq('id', itemId)
          .maybeSingle();
      final dynamic raw = row == null ? null : row['author_id'];
      final String? authorId = raw is String ? raw : null;
      if (authorId == null || authorId == uid) return;
      await PushService.notify(
        userIds: [authorId],
        title: title,
        body: body,
        category: 'activity',
        data: {'type': 'home'},
      );
    } catch (e) {
      debugPrint('FAMILY_PLANS poster push error: $e');
    }
  }

  /// Push to everyone who can see the item, except me. Fire-and-forget:
  /// a failed push must never fail the post itself.
  static Future<void> _pushToViewers({
    required String nestId,
    required List<String> visibleToIds,
    required String title,
    required String body,
  }) async {
    try {
      final uid = myId;
      final rows =
          await _db.from('nest_members').select('user_id').eq('nest_id', nestId);
      final ids = (rows as List)
          .map((r) => r['user_id'] as String?)
          .whereType<String>()
          .where((id) => id != uid)
          .where((id) => visibleToIds.isEmpty || visibleToIds.contains(id))
          .toList();
      if (ids.isEmpty) return;
      await PushService.notify(
        userIds: ids,
        title: title,
        body: body,
        category: 'activity',
        data: {'type': 'home'},
      );
    } catch (e) {
      debugPrint('FAMILY_PLANS push error: $e');
    }
  }
}
