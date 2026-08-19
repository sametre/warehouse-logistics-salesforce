# Safe Documentation Change

For the classroom exercise, the change is deliberately limited to Markdown files under `docs/academy/`.

This approach is safe because it:

- leaves deployable Salesforce metadata unchanged;
- does not alter Apex, Flow, or Lightning Web Components;
- introduces no credentials or org-specific data; and
- keeps the pull request focused and easy to review.

Each commit on this branch has one documentation purpose and a concise message.
