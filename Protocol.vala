// implementation of client protocol as defined in https://github.com/ocb2/ochat/blob/master/doc/protocol.md
// TODO: there must be a better way to generate JSON than copy-pasting all this generator garbage
namespace protocol {
	Context sync(ZMQ.Socket sock) {
		size_t length;
		var generator = new Json.Generator();
		var root = new Json.Node(Json.NodeType.OBJECT);
		var object = new Json.Object();

		root.set_object(object);
		generator.set_root(root);

		object.set_string_member("type", "SYNC");

		var s = generator.to_data(out length);
		var msg = ZMQ.Msg.with_data(s.data, free);

		msg.send(sock, 0);
		msg = ZMQ.Msg();
		msg.recv(sock);

		var parser = new Json.Parser();
		try {
			parser.load_from_data((string)msg.data, (ssize_t)msg.size());
		} catch (GLib.Error e) {
			stderr.printf("invalid json in zmq()\n");
			exit(-1);
		}

		try {
			return new Context.from_json(parser.get_root());
		} catch {
			stderr.printf("Malformed JSON in sync(): ");
			stderr.write(msg.data, msg.size());
			stderr.printf("\n");
			exit(-1);
			// return checker doesn't know about exit()
			return (Context)null;
		}
	}

	namespace server {
		List<Server> list(ZMQ.Socket sock) {
			size_t length;
			var generator = new Json.Generator();
			var root = new Json.Node(Json.NodeType.OBJECT);
			var object = new Json.Object();

			root.set_object(object);
			generator.set_root(root);

			object.set_string_member("type", "server");
			object.set_string_member("operator", "list");

			var s = generator.to_data(out length);
			var msg = ZMQ.Msg.with_data(s.data, free);

			msg.send(sock, 0);
			msg = ZMQ.Msg();
			msg.recv(sock);

			var parser = new Json.Parser();
			try {
				parser.load_from_data((string)msg.data, (ssize_t)msg.size());
			} catch (GLib.Error e) {
				stderr.printf("invalid json in zmq()\n");
				exit(-1);
			}

			try {
				List<Server> servers = new List<Server>();
			
				foreach (Json.Node n in JSON.get_array(parser.get_root()).get_elements()) {
					servers.append(new Server.from_json(n));
				}

				return servers;
			} catch {
				stderr.printf("Malformed JSON in server.list(): ");
				stderr.write(msg.data, msg.size());
				stderr.printf("\n");
				exit(-1);
				// return checker doesn't know about exit()
				return null;
			}
			
		}
	}
}