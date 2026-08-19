# Controlled Merge Conflict

A controlled conflict should use a documentation line only, never deployable Salesforce source.

1. Create two short-lived branches from the same base.
2. Edit the same line differently in a Markdown file.
3. Merge one branch, then merge the other to produce the conflict.
4. Resolve the Markdown content intentionally, stage the resolved file, and commit the merge.
5. Retain the merge commit and GitHub conversation as the evidence.

Do not manufacture a conflict or claim it is resolved until these steps are actually completed.
