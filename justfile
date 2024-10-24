
serve:
	zola serve --drafts

build:
	rm -rf docs/ | true
	zola build -o docs