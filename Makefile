# Quality gate entry points. See docs/QUALITY_GATE.md.
BASE ?= origin/main

.PHONY: quality quality-tests review

quality:
	scripts/quality/check.sh --base $(BASE)

quality-tests:
	python3 -m unittest discover -s scripts/quality/tests -t . -v

review:
	mkdir -p quality-reports
	scripts/quality/greptile_review.py --base $(BASE) --out quality-reports/greptile-$$(git rev-parse --short HEAD).json
