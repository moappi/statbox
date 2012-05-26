
SOURCE=src/statbox.opa

statbox:
	opa $(SOURCE) -o statbox

run:: statbox
	authbind ./statbox -p 80

