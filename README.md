# Ocean installer

Build the native installer with the matching compiler and stdlib:

```sh
ocean build . -o ocean-installer
```

The executable contains the installer logic in Ocean. No Python runtime or helper
is required. Git is needed to inspect tags and clone the matching stdlib; tar is
needed when selecting a dependency bundle. HTTPS uses verified libcurl transport.
When run in an interactive terminal, the installer runs inline (without an
alternate screen), printing a new section for each step and using `term/tui` for
interactive selection of installation location, dependencies, and Ocean version
(pass `--no-tui` or pipe stdin/stdout to use plain-text prompts).

The installer detects its compiled OS and architecture and lists stable-branch
release tags and `nightly-year.month.day` tags reachable from `main` on
`https://github.com/ocean-foundation/ocean`, with matching
stdlib tags. It offers `latest` (stable branch, excluding prereleases),
`latest-nightly` (dated nightly tags), or an explicit version. Neither latest option falls back to the other channel. Compiler downloads use
`ocean_<tag>_<arch>-<os>.tar`. Temporary downloads and clones are deleted after
success, cancellation, or failure. Compiler release metadata is checked against
the selected tag and recorded in `installation.json`, including version, compiler
commit/date, build date, installation date, and stdlib commit.

Choose a system directory (`/usr/local/lib/ocean` on Unix), a user directory
(`~/.local/lib/ocean`), or an absolute custom directory. Windows defaults are
Program Files/Ocean and LocalAppData/Ocean. The installer checks permissions and
requests sudo or Windows elevation when required. Existing installations display
their metadata (or unknown version) and require explicit removal confirmation.
Installation and shell PATH changes use a backup and rollback on failure.

Dependency options are skip, system package manager, or a matching release
bundle installed within the chosen Ocean directory. The bundle provides Clang,
linker, headers and libraries including libffi and libcurl, and supports a
user-local installation without administrator access. Linux bundles include a C
sysroot. macOS needs Apple's Command Line Tools SDK; setup can launch Apple's SDK
installer and asks you to rerun when it finishes. System package installation
uses apt, dnf, pacman, zypper, apk, Homebrew, or MSYS2/winget as appropriate and
requires explicit consent. Package-manager changes cannot be rolled back.

PATH configuration supports Bash, Zsh, Fish, csh and POSIX shells on Unix, and
the Windows user or machine environment. Open a new shell after installation.

Pushing an installer version tag such as `v0.1.0` runs the release workflow.
One macOS runner downloads the latest stable Ocean compiler and matching stdlib,
installs the target toolchains, and cross-builds all seven native installers.
The GitHub release contains a tar archive per target. Linux installers are
statically linked and use the system CA store and c-ares for DNS. Windows
installers statically link libcurl and libffi and use Windows Schannel for TLS.
The Windows archives contain the executable and third-party license notices.
macOS installers use the libraries provided by macOS. The compiler's dependency
bundles are separate `ocean-deps_<tag>_<arch>-<os>.tar.xz` assets.

Validation:

```sh
ocean test . --notty
python3 test_native_installer.py ./ocean-installer
```

Python is used only by the offline integration test driver, which creates local
repositories and a loopback HTTP fixture. It also tests the serialized system-wide
apply plan with a fake package manager and temporary profile paths. It never
installs system packages or requires elevation.
