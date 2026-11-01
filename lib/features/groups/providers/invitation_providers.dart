import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/firebase/firebase_providers.dart';
import '../../auth/providers/auth_providers.dart';
import '../data/firestore_group_repository.dart';
import '../data/firestore_invitation_repository.dart';
import '../data/invitation_repository.dart';
import 'group_providers.dart';

// Explicit development/fake repositories do not initialize Firebase SDKs.
final invitationRepositoryProvider = Provider<InvitationRepository?>((ref) {
  if (ref.watch(groupRepositoryProvider) is! FirestoreGroupRepository) {
    return null;
  }
  return FirestoreInvitationRepository(
      ref.watch(firestoreProvider), ref.watch(firebaseAuthProvider));
});
final pendingInvitationsProvider = StreamProvider<List<GroupInvitation>>((ref) {
  final user =
      ref.watch(currentUserProvider.select((u) => (u?.id, u?.profileComplete)));
  if (user.$1 == null || user.$2 != true) return Stream.value(const []);
  return ref.watch(invitationRepositoryProvider)?.watchPending() ??
      Stream.value(const []);
});
final membershipNotificationsProvider =
    StreamProvider<List<MembershipNotification>>((ref) {
  final user =
      ref.watch(currentUserProvider.select((u) => (u?.id, u?.profileComplete)));
  if (user.$1 == null || user.$2 != true) return Stream.value(const []);
  return ref.watch(invitationRepositoryProvider)?.watchNotifications() ??
      Stream.value(const []);
});
