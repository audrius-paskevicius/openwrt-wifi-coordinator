.PHONY: check test prepare-tests test-ucode package

check:
	python3 scripts/check-project.py
	node tests/check-ui.cjs
	sh -n wifi-coordinator/build-apk.sh
	sh -n scripts/test-ucode.sh

prepare-tests:
	python3 scripts/prepare-tests.py

test-ucode: prepare-tests
	sh scripts/test-ucode.sh

test: check test-ucode

package:
	sh wifi-coordinator/build-apk.sh
