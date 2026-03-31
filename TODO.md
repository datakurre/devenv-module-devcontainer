# TODO

## devcontainer firewall

* Remove --cap-add=NET_ADMIN from .devcontainer.json and give the firewall script its caps via setcap instead — but that requires root at image build time and therefore require a custom image.
