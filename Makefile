.PHONY: install run clean

install:
	python3 -m venv .venv
	. .venv/bin/activate && pip install -r requirements.txt

run:
	. .venv/bin/activate && func start

clean:
	rm -rf .venv