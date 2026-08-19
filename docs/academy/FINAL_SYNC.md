# Final Main Synchronization

After the pull request is merged, synchronize the local repository without force-pushing:

```bash
git switch main
git pull --ff-only origin main
git status --short --branch
```

Expected final state: local `main` tracks `origin/main`, the working tree is clean, and the documentation branch has been merged through GitHub.
