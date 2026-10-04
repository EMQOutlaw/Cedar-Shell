# Private upload review

Scope: the complete CEDAR source snapshot, helpers, built-in bundles, themes, local identity content, documentation, tests, installation/recovery tools, and CI. The initial repository contains a new source history; no personal development history is imported.

The local source scan checks machine identity, personal home paths, private network addresses, credential signatures, and runtime artifacts without printing matching values. Additional review covers staged paths, credential-bearing URLs, email patterns, hardware addresses, cloud credentials, and PNG metadata. The test email is a reserved synthetic example. Artwork includes image-generation provenance; required attribution and provenance are retained. Preview images contain no visible account, hostname, network name, private path, or credential.

Backups, user preferences, logs, caches, private credentials, and local histories are excluded. The verified GitHub repository URL is intentional project metadata. Commit author and committer use only the owner's approved GitHub account and noreply attribution. No personal email or personal name is required.

This review is not a guarantee that heuristic scanning recognizes every possible secret. New changes require review before upload. CI repeats source scanning but does not replace review of history and metadata.

The destination must remain private. First-party source remains unlicensed by the owner's instruction; upstream notices remain intact. Public publication requires a separate explicit approval and completion of the release gates in RELEASE-READINESS.md.
