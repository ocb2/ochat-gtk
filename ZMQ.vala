// networking thread, communicates to main thread via ZMQ inproc pair socket
void *zmq() {
    var sock_sub = ZMQ.Socket.create(ctx, ZMQ.SocketType.SUB);
 	var sock_req = ZMQ.Socket.create(ctx, ZMQ.SocketType.REQ);
	var sock_pair = ZMQ.Socket.create(ctx, ZMQ.SocketType.PAIR);

	sock_sub.setsockopt<string>(ZMQ.SocketOption.SUBSCRIBE, "", 0);

	sock_sub.connect("tcp://127.0.0.1:6000");
	sock_req.connect("tcp://127.0.0.1:6001");
	sock_pair.connect("inproc://msg");

	ZMQ.POLL.PollItem poll_sub = {sock_sub, 0, ZMQ.POLL.IN, 0 };
	ZMQ.POLL.PollItem poll_req = {sock_req, 0, ZMQ.POLL.IN, 0 };
	ZMQ.POLL.PollItem poll_pair = {sock_pair, 0, ZMQ.POLL.IN, 0 };

	// vala copies these, so you have to index items not reference eg poll_sub
	ZMQ.POLL.PollItem[] items = {poll_sub, poll_req, poll_pair};

	while (true) {
		var n = ZMQ.POLL.poll(items, items.length, -1);
		assert(n >= 0);

		// SUB
		if (items[0].revents > 0) {
			var msg = ZMQ.Msg();
			// TODO: check return?
		    msg.recv(sock_sub, 0);

			var parser = new Json.Parser();
			try {
				parser.load_from_data((string)msg.data, (ssize_t)msg.size());
			} catch (GLib.Error e) {
				stderr.printf("invalid json in zmq()\n");
				exit(-1);
			}
			var root = parser.get_root();
			if (root == null) {
				stderr.printf("Malformed response: ");
				stderr.write(msg.data, msg.size());
				stderr.printf("\n");
				continue;
			} else {
				try {
					if (JSON.get_string(Json.Path.query("$.operand", root)) == "sync") {
						var new_ctx = new Context.from_json(root);
						queue.push(new Right<Msg, Context>(new_ctx));
						irc_ctx = new_ctx;
					} else {
						try {
							queue.push(new Left<Msg, Context>(new Msg.from_json(root)));
						} catch (JSON.Error.MALFORMED e) {
							stderr.printf("Malformed JSON: %s\n", Json.to_string(root, true));
							continue;
						}
					}
				} catch {
					stderr.printf("Malformed JSON: %s\n", Json.to_string(root, true));
					continue;
				}
			}
		}

		// PAIR
		// just ferries messages between threads basically
		if (items[2].revents > 0) {
			var msg = ZMQ.Msg();
			msg.recv(sock_pair, 0);
			msg.send(sock_req, 0);
			msg = ZMQ.Msg();
			msg.recv(sock_req, 0);
			msg.send(sock_pair, 0);
		}
	}
}

Context zmq_sync(ZMQ.Socket sock_req) {
	size_t length;
	var generator = new Json.Generator();
	var root = new Json.Node(Json.NodeType.OBJECT);
	var object = new Json.Object();
	root.set_object(object);
	generator.set_root(root);
	object.set_string_member("type", "SYNC");
	var s = generator.to_data(out length);
	
	var msg = ZMQ.Msg.with_data(s.data, free);
	msg.send(sock_req, 0);
	msg = ZMQ.Msg();
	msg.recv(sock_req);
	var parser = new Json.Parser();
	try {
		parser.load_from_data((string)msg.data, (ssize_t)msg.size());
	} catch (GLib.Error e) {
		stderr.printf("invalid json in zmq()\n");
		exit(-1);
	}
	var ctxroot = parser.get_root();
	try {
		return new Context.from_json(ctxroot);
	} catch {
		stderr.printf("Malformed JSON in sync(): ");
		stderr.write(msg.data, msg.size());
		stderr.printf("\n");
		exit(-1);
		// return checker doesn't know about exit()
		return (Context)null;
	}
}
