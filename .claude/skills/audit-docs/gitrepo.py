"""Git helpers shared by map-docs.py and check-conf.py."""
import subprocess
import sys


def run(cmd):
    # stdout/stderr/universal_newlines rather than capture_output/text: RHEL 8 ships Python 3.6.
    return subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                          universal_newlines=True).stdout


def git(root, *args):
    return run(["git", "-C", root, *args])


def repo_root(start="."):
    """The top folder of the git repo that holds start; exits when there is none."""
    root = run(["git", "-C", start, "rev-parse", "--show-toplevel"]).strip()
    if not root:
        sys.exit(f"{start} is not inside a git repo")
    return root


def repo_files(root, *patterns):
    """The repo's tracked and untracked files that match the patterns, minus ignored ones, relative to root."""
    out = git(root, "ls-files", "-z", "--cached", "--others", "--exclude-standard", "--", *patterns)
    return sorted(p for p in out.split("\0") if p)
