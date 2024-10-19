
serve:
	zola serve

build:
	rm -rf docs/ | true
	zola build -o docs