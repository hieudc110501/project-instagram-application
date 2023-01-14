import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:instagram_clone_course/state/comments/extensions/comment_sorting_by_request.dart';
import 'package:instagram_clone_course/state/comments/models/comment.dart';
import 'package:instagram_clone_course/state/comments/models/post_comment_request.dart';
import 'package:instagram_clone_course/state/comments/models/post_with_comments.dart';
import 'package:instagram_clone_course/state/constants/firebase_collection_name.dart';
import 'package:instagram_clone_course/state/constants/firebase_field_name.dart';
import 'package:instagram_clone_course/state/posts/models/post.dart';

final specificPostWithCommentsProvider = StreamProvider.family
    .autoDispose<PostWithComments, RequestForPostAndComments>(
  (
    ref,
    RequestForPostAndComments request,
  ) {
    final controller = StreamController<PostWithComments>();

    Post? post;
    Iterable<Comment>? comments;

    void notify() {
      final localPost = post;
      if (localPost == null) {
        return;
      }
      final outputComments = (comments ?? []).applySortingFrom(request);

      final result = PostWithComments(
        post: localPost,
        comments: outputComments,
      );
      controller.sink.add(result);
    }

    //watch changes to the post
    final postSub = FirebaseFirestore.instance
        .collection(FirebaseCollectionName.posts)
        .where(FieldPath.documentId, isEqualTo: request.postId)
        .limit(1)
        .snapshots()
        .listen((snapshot) {
      if (snapshot.docs.isEmpty) {
        post = null;
        comments = null;
        notify();
        return;
      }
      final doc = snapshot.docs.first;
      if (doc.metadata.hasPendingWrites) {
        return;
      }
      post = Post(
        postId: doc.id,
        json: doc.data(),
      );
      notify();
    });

    //watch changes to the commment
    final commentsQuery = FirebaseFirestore.instance
        .collection(FirebaseCollectionName.comments)
        .where(FirebaseFieldName.postId, isEqualTo: request.postId)
        .orderBy(FirebaseFieldName.createdAt, descending: true);

    // get amount of comments
    final limitedCommentQuery = request.limit != null
        ? commentsQuery.limit(request.limit!)
        : commentsQuery;

    final commentsSub = limitedCommentQuery.snapshots().listen(
      (snapshot) {
        comments = snapshot.docs
            .where(
              (doc) => doc.metadata.hasPendingWrites,
            )
            .map(
              (doc) => Comment(
                doc.data(),
                id: doc.id,
              ),
            )
            .toList();
        notify();
      },
    );

    ref.onDispose(() {
      commentsSub.cancel();
      postSub.cancel();
      controller.close();
    });

    return controller.stream;
  },
);
