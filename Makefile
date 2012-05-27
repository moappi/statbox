SRCLIBS=src/stdlib/dropbox.opa
LIBS=custom.stdlib.apis.dropbox.opx

SOURCES=src/statbox.opa

statbox: $(LIBS) $(SOURCES)
	opa $(SOURCES) -o statbox

$(LIBS): $(SRCLIBS)
	opa -c --parser classic $^

run:: statbox
	killall statbox || true
	authbind ./statbox -p 80

clean::
	rm -rf _build _tracks $(LIBS) statbox

## hackish: use with care
make deploy::
	git push -f origin master:deploy && \
	ssh "$(USER)@$(HOST)" 'cd git/statbox && git fetch && git checkout deploy && git pull origin deploy && make run'

make clean-deploy::
	git push -f origin master:deploy && \
	ssh "$(USER)@$(HOST)" 'cd git/statbox && make clean && git fetch && git checkout deploy && git pull origin deploy && make run'
