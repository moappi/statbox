## build rules

SRCDIR=src
SOURCES=$(addprefix $(SRCDIR)/,pool.opa data.opa config.opa session.opa server.opa main.opa view.opa)
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
MONGO=$(BINPATH)/mongo

mongo-flush::
	$(MONGO) entries --quiet --eval "db.all.remove({})"
	$(MONGO) users --quiet --eval "db.all.remove({})"

mongo-init::
	$(MONGO) entries --quiet --eval 'db.all.ensureIndex({ "uid":1, "parent.some":1 });'
	$(MONGO) entries --quiet --eval 'db.all.ensureIndex({ "uid":1, "parent":1 });'
#TODO: figure out which one is useful

mongo-stats::
	$(MONGO) users --quiet --eval "db.all.find().count()"
	$(MONGO) entries --quiet --eval "db.all.find().count()"

run:: statbox
	killall statbox || true
	mkdir -p $(DBPATH)
	killall -s CONT mongod || ($(BINPATH)/mongod --dbpath $(DBPATH) && make mongo-init) &
	make mongo-stats
	authbind ./statbox -p 80

clean-all:: clean
	@echo "Press enter to reset tables 'users' and 'entries' of MongoDB" && read i && [ "xx$$i" = "xx" ]
	make mongo-flush mongo-init
	rm -rf access.log error.log

deploy::
	git push -f origin master:deploy && \
	ssh "$(USER)@$(HOST)" 'cd git/statbox && git fetch && git checkout deploy && git reset --hard origin/deploy && make run'

clean-deploy::
	git push -f origin master:deploy && \
	ssh "$(USER)@$(HOST)" 'cd git/statbox && make clean && git fetch && git checkout deploy && make clean-all && git reset --hard origin/deploy && make run'
