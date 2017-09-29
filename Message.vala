using Sqlite;

public class Prefix : Object {
	public bool discriminant;

	public string server;

	public string nick;
	public string ident;
	public string host;

	// if it has a prefix, then it should have either a server, or a nick/ident/host pair, if not, it's malformed
	// TODO: allow messages without prefixes
	public Prefix.from_json(Json.Node node) throws JSON.Error {
		try {
			this.server = JSON.get_string(Json.Path.query("$.prefix.server", node));
			this.discriminant = false;
		} catch (Json.PathError e) {
			try {
				this.nick = JSON.get_string(Json.Path.query("$.prefix.nick", node));
				this.ident = JSON.get_string(Json.Path.query("$.prefix.ident", node));
				this.host = JSON.get_string(Json.Path.query("$.prefix.host", node));
				this.discriminant = true;

			} catch (Json.PathError e) {
				throw new JSON.Error.NO_SUCH_KEY("");
			} catch {
				throw new JSON.Error.MALFORMED("");
			}
		} catch {
			throw new JSON.Error.MALFORMED("");
		}
	}

	public Json.Object to_json() {
		var generator = new Json.Generator();
		var root = new Json.Node(Json.NodeType.OBJECT);
		var object = new Json.Object();
		size_t length;
		root.set_object(object);
		generator.set_root(root);
		if (discriminant) {
			object.set_string_member("nick", this.nick);
			object.set_string_member("ident", this.ident);
			object.set_string_member("host", this.host);
		} else {
			object.set_string_member("server", this.server);
		}

		return object;
	}
}

public class Msg : Object {
	public Perhaps<Prefix> prefix;
	public string command;
	public string[] parameters;

	public Msg(Perhaps<Prefix> prefix, string command, string[] parameters) {
		this.prefix = prefix;
		this.command = command;
		this.parameters = parameters;
	}

	public Msg.from_json(Json.Node node) throws JSON.Error {
		try {
			this.prefix = new Some<Prefix>(new Prefix.from_json(node));
		} catch (JSON.Error.NO_SUCH_KEY e) {
			this.prefix = new None<Prefix>();
		} catch (JSON.Error.MALFORMED e) {
			throw new JSON.Error.MALFORMED("prefix");
		}

		try {
			this.command = JSON.get_string(Json.Path.query("$.command", node));
		} catch {
			throw new JSON.Error.MALFORMED("command");
		}

		try {
			var ps = JSON.get_array(Json.Path.query("$.params", node));
			this.parameters = new string[ps.get_length()];
			for (int i = 0; i < ps.get_length(); i++) {
				parameters[i] = ps.get_string_element(i);
			}
		} catch {
			throw new JSON.Error.MALFORMED("parameters");
		}
	}

	public string serialize() {
		var generator = new Json.Generator();
		var root = new Json.Node(Json.NodeType.OBJECT);
		var object = new Json.Object();
		size_t length;
		root.set_object(object);
		generator.set_root(root);
		object.set_string_member("type", "IRC");
		if (this.prefix is Some) {
			object.set_object_member("prefix", (this.prefix as Some<Prefix>).data.to_json());
		}
		object.set_string_member("command", this.command);

		var ps = new Json.Array.sized(this.parameters.length);
		for (int i = 0; i < this.parameters.length; i++) {
			ps.add_string_element(this.parameters[i]);
		}
		object.set_array_member("params", ps);

		return generator.to_data(out length);
	}

	public Perhaps<string> recipient() {
		string s;

		switch (this.command) {
		case "JOIN":
		case "PART":
		case "PRIVMSG": {
			s = this.parameters[0];
			break;
		}
		default: { return new None<string>(); }
		}

		return new Some<string>(s.dup());
	}
}