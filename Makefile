.PHONY: test
test:
	emacs --batch -L . -L tests -l crystal-mode-tests.el -f ert-run-tests-batch
