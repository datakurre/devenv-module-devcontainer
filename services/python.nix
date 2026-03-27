# Python allowlist — PyPI package index and uv toolchain.
#
# Covers pip, poetry, uv, twine, and other Python package tools.
# astral.sh is contacted by `uv self update` before redirecting to GitHub Releases.
{
  hosts = [
    "pypi.org"                # package index / simple API
    "files.pythonhosted.org"  # package file downloads (CDN origin)
    "upload.pypi.org"         # twine / poetry publish endpoint
    "astral.sh"               # uv self-update redirect origin
  ];

  cidrs = [];
}
