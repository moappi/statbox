## build rules

SRCDIR=src
SOURCES=$(addprefix $(SRCDIR)/,data.opa statbox.opa)

LIBDIR=src/stdlib
LIBS=custom.stdlib.apis.common.opx custom.stdlib.apis.oauth.opx custom.stdlib.apis.dropbox.opx

statbox: $(LIBS) $(SOURCES)
	opa $(SOURCES) -o statbox

custom.stdlib.apis.common.opx: $(LIBDIR)/api_libs.opa
	opa -c --parser classic $^

custom.stdlib.apis.oauth.opx: $(LIBDIR)/oauth.opa
	opa -c --parser classic $^

custom.stdlib.apis.dropbox.opx: $(LIBDIR)/dropbox.opa
	opa -c --parser classic $^

clean::
	rm -rf _build _tracks .opx/* $(LIBS) statbox

## hackish deployment scripts: use with care
DBPATH=$(HOME)/var/mongodb
BINPATH=$(HOME)/bin

run:: statbox
	killall mongod || true
	mkdir -p $(DBPATH)
	$(BINPATH)/mongod --dbpath $(DBPATH) &
	killall statbox || true
	authbind ./statbox -p 80

clean-all:: clean
	@echo "Press enter to reset the database in $(DBPATH)" && read i && [ "xx$$i" = "xx" ]
	rm -rf $(DBPATH)/* access.log error.log

deploy::
	git push -f origin master:deploy && \
	ssh "$(USER)@$(HOST)" 'cd git/statbox && git fetch && git checkout deploy && git pull origin deploy && make run'

clean-deploy::
	git push -f origin master:deploy && \
	ssh "$(USER)@$(HOST)" 'cd git/statbox && make clean && git fetch && git checkout deploy && make clean-all && git pull origin deploy && make run'
