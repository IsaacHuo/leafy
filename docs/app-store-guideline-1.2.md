# App Store Guideline 1.2 Resubmission Notes

Use this checklist when submitting build `1.0 (17)` for Guideline 1.2 review.

## App Store Connect Checklist

- Set the app age rating to `18+` by using `Override to Higher Age Rating` if the questionnaire calculates a lower rating.
- In `In-App Controls`, set both `Parental Controls` and `Age Assurance` to `None`; Leafy does not provide those Apple-defined mechanisms.
- Add a custom EULA or terms URL in App Store Connect.
- Mention the community safety changes in Review Notes.
- Deploy the Supabase migration before review.
- Deploy the `admin-community` Edge Function before review.

## Custom EULA / Community Terms

Leafy has zero tolerance for objectionable content and abusive users. By using community features, users agree not to post, upload, comment, or share content that is abusive, harassing, threatening, hateful, sexually explicit, illegal, spam, fraudulent, or that exposes private personal information. Users also agree not to impersonate others, evade moderation, or abuse anonymous posting.

Leafy may filter, reject, hide, or delete objectionable posts and comments. Users can report posts, comments, users, and inappropriate activity from inside the app. Reported content may be removed from public feeds immediately while reviewed. Users can block abusive users, and blocked users' content will be hidden from the blocker.

Leafy will review reports of objectionable content within 24 hours. When a violation is confirmed, Leafy will remove or hide the offending content and eject, ban, mute, or otherwise restrict the user who provided it.

For community safety reports, contact `support@myleafy.space` or use `我的 -> 支持 -> 举报与反馈 -> 社区安全` in the app.

## Review Notes Draft

We updated Leafy to comply with Guideline 1.2 for anonymous user-generated content.

- Age rating is configured as 18+ to reflect anonymous UGC and moderation requirements. `Parental Controls` and `Age Assurance` are set to `None`.
- Users must agree to community terms before using posting or commenting features. The terms state zero tolerance for objectionable content and abusive users.
- Text posts and comments are validated server-side. Objectionable content is rejected before publishing.
- Posts with images are saved as `pending_review` and do not appear in public feeds until approved by an administrator.
- Every post and comment has a `...` menu with report, block user, and delete actions where applicable.
- When a user reports a post or comment, the reported content is immediately hidden from the reporter and moved out of the public feed for moderation.
- Users can block abusive users. Blocked authors are filtered from feeds, post details, comments, and notifications.
- Users can immediately delete their own posts from feed/detail views.
- The in-app support screen includes `举报与反馈`, where users can choose `社区安全`, and the support screen shows `support@myleafy.space`.
- The admin console now includes a report queue with 24-hour SLA visibility, actions to hide content, mute users, resolve or reject reports, and audit logging.

Reviewer path: open the Discover/community feed, attempt to compose or comment, accept the community terms, use the `...` menu on a post or comment to report/block/delete, and open `我的 -> 支持 -> 举报与反馈` for contact/reporting information.
