// networking thread, communicates to main thread via ZMQ inproc pair socket and asychronous queue
// the queue corresponds to messages recieved on the subscriber socket, while the inproc pair
// corresponds to messages to be sent and recieved via the req socket
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
					if (JSON.query_string("$.operand", root) == "sync") {
						var new_ctx = new Context.from_json(root);
						queue.push(new Right<Msg, Context>(new_ctx));
						irc_ctx = new_ctx;
					}
				} catch {
					try {
						queue.push(new Left<Msg, Context>(new Msg.from_json(root)));
					} catch (JSON.Error e) {
						stderr.printf("Malformed JSON in message: %s\n", Json.to_string(root, true));
						continue;
					}
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