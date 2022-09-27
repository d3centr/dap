# Releases

- Every branch is a release.
- Versioned releases are branches named majorVersion.minorVersion, e.g. `0.1`.
- There is no explicit patch version, it is replaced by a git commit on the versioned branch.
- Linear commits of a versioned branch mirror implicit and monotonic patch versions,\
    e.g. `git checkout HEAD~~` takes you 2 patch versions backwards.

## Version Freeze

*How to freeze the patch version of a release?*

To freeze a release on a given commit, you should fork and manage your own release branch, which is as easy as changing the URL of DaP REPO parameter. See the 3 ways to do so at the beginning of deployment [readme](/bootstrap).

*Why?*

In general, automation is preferred within DaP. By prioritized design, we don't fully support manual patch updates (even though Argo CD does). It is mostly due to build jobs always pulling the HEAD of a branch. You'll notice that `DaP_branch` parameter is always passed to Argo CD `--revision` flag, which could take a commit, but build jobs wouldn't be aware.

