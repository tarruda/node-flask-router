TESTS = ./test/support/http.js ./test/router.coffee

test:
	@./node_modules/.bin/mocha --require should --compilers coffee:coffee-script $(TESTS) 

test-docs:
	@./node_modules/.bin/mocha --reporter doc --require should --compilers coffee:coffee-script $(TESTS) > tests.html

compile:
	@./node_modules/.bin/coffee -o lib src

link: test compile
	npm link

.PHONY: test
