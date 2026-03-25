# PyPI allowlist — Python Package Index download and upload.
{
  hosts = [
    "pypi.org"                # package index / simple API
    "files.pythonhosted.org"  # package file downloads (CDN origin)
    "upload.pypi.org"         # twine / poetry publish endpoint
  ];

  cidrs = [];
}
