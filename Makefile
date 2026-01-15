.PHONY: shell
shell:
	devenv shell

.PHONY: develop
develop:
	devenv shell -- code .

devenv.local.nix:
	cp devenv.local.nix.example devenv.local.nix
