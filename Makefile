all: main.vala JSON.vala Message.vala ZMQ.vala Perhaps.vala zmq.vapi
	valac -g --thread --enable-checking --Xcc=-lzmq --pkg gtk+-3.0 --pkg json-glib-1.0 --pkg sqlite3 main.vala JSON.vala Message.vala ZMQ.vala Protocol.vala ServerListDialogue.vala Perhaps.vala zmq.vapi -o ochat-gtk

test: ochat-gtk
	gdb -ex r --args ./ochat-gtk