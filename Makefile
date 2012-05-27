SRCLIBS=src/stdlib/dropbox.opa
LIBS=custom.stdlib.apis.dropbox.opx

SOURCES=src/statbox.opa

statbox: $(LIBS) $(SOURCES)
	opa $(SOURCES) -o statbox

$(LIBS): $(SRCLIBS)
	opa -c --parser classic $^

run:: statbox
	authbind ./statbox -p 80

clean::
	rm -rf _build _tracks $(LIBS) statbox

make deploy::
	git push -f origin deploy && \
	ssh "$(USER)@$(HOST)" 'cd git/statbox && make clean && git checkout -t origin/deploy && git reset -f origin/deploy && make run'
