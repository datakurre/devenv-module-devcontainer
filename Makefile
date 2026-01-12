.PHONY: shell
shell:
	devenv shell

.PHONY: develop
develop:
	devenv shell -- code .
