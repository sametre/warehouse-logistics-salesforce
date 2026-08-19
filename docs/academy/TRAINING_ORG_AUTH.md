# Training Org Authentication

The training org is authenticated through Salesforce CLI with a local alias. Authentication is kept outside source control; no access token, session value, password, or authorization URL is stored in this repository.

Example command:

```bash
sf org login web --alias WMS_DEV
sf org list --all
```

Before a deployment, confirm the intended alias and run a validation command first. This branch does not deploy metadata.
