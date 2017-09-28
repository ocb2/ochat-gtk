all:
	valac -g --thread --enable-checking --Xcc=-lzmq --pkg gtk+-3.0 --pkg json-glib-1.0 --pkg sqlite3 main.vala Message.vala ZMQ.vala Perhaps.vala zmq.vapi

test: all
	gdb -ex r --args ./rschatc