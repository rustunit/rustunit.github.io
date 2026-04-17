
serve:
	ZOLA_SERVE=1 zola serve

build:
	rm -rf docs/ | true
	zola build -o docs