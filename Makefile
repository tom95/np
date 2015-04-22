CFLAGS=$(shell pkg-config --cflags nice)
LDLIBS=$(shell pkg-config --libs nice)

all: nice server

nice: nice.vala
	valac --pkg nice --pkg libsoup-2.4 --pkg json-glib-1.0 --vapidir=. nice.vala -o nice -g -X -g

server: server.vala
	valac --pkg libsoup-2.4 --pkg json-glib-1.0 server.vala -g -X -g -o server

sample: sample.o
