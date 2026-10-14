# Public repository contents

**English** | [Русский](REPOSITORY_PRIVACY.ru.md)

Git contains source code, model catalogs, dependency manifests, licenses, synthetic test data and technical documentation. Kat's own code is GPL-3.0-or-later; third-party material keeps its own terms.

Do not commit secrets, local paths or device identifiers, signing material, personal text/images/audio, app containers, build outputs or downloaded weights. Internal instructions, assistant journals, internal plans and discussion archives stay local and are excluded from Git.

Before committing, check the contents, file sizes and the staged diff. A commit message briefly describes the change. Use synthetic data in reports and tests. Required author names and notices of third-party components are preserved. Public project contact: katlabs.dev@gmail.com.

Do not push local archives or internal refs, and do not use `push --mirror`. Only the reviewed `main` branch is updated. Rewriting a branch does not guarantee that old objects and caches are removed from the hosting service.
