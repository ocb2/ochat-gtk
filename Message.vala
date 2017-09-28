using Sqlite;

public class Prefix : Object {
	public bool discriminant;
	public string server;
	public string nick;
	public string ident;
	public string host;

	public Prefix.from_json(Json.Object root) {
		Json.Object prefix;
		try {
			prefix = root.get_object_member("prefix");

			this.discriminant = false;
			this.server = prefix.get_string_member("server");
			if (this.server == null) { throw new Error(0, 0, ""); }
			stdout.printf("in prefix constructor, in false discriminant branch, this.server=%p\n", this.server);
		} catch (Error e) {
			this.discriminant = true;
			this.nick = prefix.get_string_member("nick");
			this.ident = prefix.get_string_member("ident");
			this.host = prefix.get_string_member("host");
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

	public Msg.from_json(Json.Object root) {
		try {
			var p = new Prefix.from_json(root);
			this.prefix = new Some<Prefix>(p);

			this.command = root.get_string_member("command");

			var ps = root.get_array_member("params");
			this.parameters = new string[ps.get_length()];
			for (int i = 0; i < ps.get_length(); i++) {
				parameters[i] = ps.get_string_element(i);
			}
		} catch (Error e) {
			this.prefix = new None<Prefix>();
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
/*
public interface Msg : Object {
	public abstract string get_recipient();
	public abstract string to_string();
	public static string serialize() {
		return (string)null;
	}
	public static Msg from_json(Json.Object root) {
		Msg r;

		switch (root.get_string_member("command")) {
		case "JOIN": {
		    r = new JOIN.from_json(root);
			break;
		}
		case "PART": {
		    r = new PART.from_json(root);
			break;
		}
		case "PRIVMSG": {
		    r = new PRIVMSG.from_json(root);
			break;
		}
		default: {
			r = null;
			break;
		}
		};

		return r;
	}
}

public class User : Object {
	public string nick;
	public string ident;
	public string host;

	public User(string nick, string i, string h) {
		this.nick = nick;
		this.ident = i;
		this.host = h;
	}

	public User.from_json(Json.Object root) {
		var prefix = root.get_object_member("prefix");
		this.nick = prefix.get_string_member("nick");
	    this.ident = prefix.get_string_member("ident");
	    this.host = prefix.get_string_member("host");
	}

	public string to_string() {
		return this.nick +
		"!" +
		this.ident +
		"@" +
		this.host;
	}
}

public class JOIN : Msg, Object {
	public User user;
	public string channel;
    public JOIN(User u, string c) {
		user = u;
		channel = c;
	}
	public string get_recipient() {
		return channel;
	}
	public string to_string() {
		return "join: " +
		user.to_string() +
		" to " +
		channel +
		"\n";
	}

	public static string serialize(string channel) {
		var generator = new Json.Generator();
		var root = new Json.Node(Json.NodeType.OBJECT);
		var object = new Json.Object();
		size_t length;
		root.set_object(object);
		generator.set_root(root);
		object.set_string_member("operand", "JOIN");
		object.set_string_member("channel", channel);
		return generator.to_data(out length);
	}

	public JOIN.from_json(Json.Object root) {
		this.user = new User.from_json(root);
		this.channel = root.get_array_member("params").get_string_element(0);
	}
}
public class PART : Msg, Object {
	public User user;
	public string channel;
	public string reason;
	public PART(User u, string c, string r) {
		user = u;
		channel = c;
		reason = r;
	}
	public string get_recipient() {
		return channel;
	}
	public string to_string() {
		return "part: " +
		user.to_string() +
		" from " +
		channel +
		": " +
		reason +
		"\n";
	}

	public static string serialize(string channel, string reason) {
		size_t length;
		var generator = new Json.Generator();
		var root = new Json.Node(Json.NodeType.OBJECT);
		var object = new Json.Object();
		root.set_object(object);
		generator.set_root(root);
		object.set_string_member("operand", "PART");
		object.set_string_member("channel", channel);
		object.set_string_member("reason", reason);
		return generator.to_data(out length);
	}

	public PART.from_json(Json.Object root) {
		this.user = new User.from_json(root);
		this.channel = root.get_array_member("params").get_string_element(0);
		this.reason = root.get_array_member("params").get_string_element(1);
	}
}

// do we even need this here?
public class PING : Object {
	public string server;
    public PING(string s) {
		server = s;
	}
}

public class PRIVMSG : Msg, Object {
	public User user;
	public string recipient;
	public string body;
    public PRIVMSG(User u, string r, string b) {
		this.user = u;
	    this.recipient = r;
		this.body = b;
	}
	public string get_recipient() {
		if (this.recipient == irc_ctx.nick) {
			return this.user.nick;
		} else {
			return this.recipient;
		}
	}
	public string to_string() {
		return
		user.to_string() +
		": " +
		body +
		"\n";
	}

	public static string serialize(string recipient, string body) {
		size_t length;
		var generator = new Json.Generator();
		var root = new Json.Node(Json.NodeType.OBJECT);
		var object = new Json.Object();
		root.set_object(object);
		generator.set_root(root);
		object.set_string_member("operand", "PRIVMSG");
		object.set_string_member("recipient", recipient);
		object.set_string_member("body", body);
		return generator.to_data(out length);
	}

	public PRIVMSG.from_json(Json.Object root) {
		this.user = new User.from_json(root);
		this.recipient = root.get_array_member("params").get_string_element(0);
		this.body = root.get_array_member("params").get_string_element(1);
	}
}*/