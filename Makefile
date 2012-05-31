## build rules

SRCDIR=src
SOURCES=$(addprefix $(SRCDIR)/,data.opa config.opa session.opa server.opa main.opa view.opa)
RESOURCES=resources/*

LIBDIR=src/stdlib
LIBS=custom.stdlib.apis.common.opx custom.stdlib.apis.oauth.opx custom.stdlib.apis.dropbox.opx

PLUGINS=encode.opp

statbox: $(LIBS) $(SOURCES) $(RESOURCES) $(PLUGINS)
	opa $(PLUGINS) $(SOURCES) -o statbox --slicer-dump

custom.stdlib.apis.common.opx: $(LIBDIR)/api_libs.opa
	opa -c --parser classic $^

custom.stdlib.apis.oauth.opx: $(LIBDIR)/oauth.opa
	opa -c --parser classic $^

custom.stdlib.apis.dropbox.opx: $(LIBDIR)/dropbox.opa
	opa -c --parser classic $^

%.opp: plugins/%.js plugins/%.ml
	opa-plugin-builder --js-validator-off $^ -o $@

clean::
	rm -rf _build _tracks $(PLUGINS) .opx/* $(LIBS) $(LIBS:.opx=.opx.broken) statbox

## hackish deployment scripts: use with care
DBPATH=$(HOME)/var/mongodb
BINPATH=$(HOME)/bin

run:: statbox
	killall mongod || true
	killall statbox || true
	mkdir -p $(DBPATH)
	$(BINPATH)/mongod --dbpath $(DBPATH) &
	authbind ./statbox -p 80

clean-all:: clean
	@echo "Press enter to reset the database in $(DBPATH)" && read i && [ "xx$$i" = "xx" ]
	rm -rf $(DBPATH)/* access.log error.log

deploy::
	git push -f origin master:deploy && \
	ssh "$(USER)@$(HOST)" 'cd git/statbox && git fetch && git checkout deploy && git reset --hard origin/deploy && make run'

clean-deploy::
	git push -f origin master:deploy && \
	ssh "$(USER)@$(HOST)" 'cd git/statbox && make clean && git fetch && git checkout deploy && make clean-all && git reset --hard origin/deploy && make run'
