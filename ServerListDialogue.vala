// TODO: this should have a better name, and probably be in a namespace
// this is specifically an IRC server, but since we don't support any other
// protocols, it's just a server for now
public class Server : Object {
	public string id;
	public string host;
	public short port;
	public string nick;
	public string ident;
	public string real;
	
	public Server.from_json(Json.Node node) throws JSON.Error {
		try {
			this.id = JSON.query_string("$.id", node);
			this.host = JSON.query_string("$.host", node);
			this.port = (short)JSON.query_int("$.port", node);
			this.nick = JSON.query_string("$.nick", node);
			this.ident = JSON.query_string("$.ident", node);
			this.real = JSON.query_string("$.realname", node);
		} catch {
		    throw new JSON.Error.MALFORMED("server");
		}

	}
}

public class ServerList : Gtk.Bin {
	public ServerList(List<Server> servers) {
		var model = new Gtk.ListStore(1, typeof(string));

		var view = new Gtk.TreeView();
		view.set_model(model);
		view.insert_column_with_attributes(-1, "Server", new Gtk.CellRendererText(), "text", 0);

		Gtk.TreeIter iter;
		model.append(out iter);
		model.set(iter, 0, "localhost");

		this.add(view);
		this.show_all();
	}
}

public class ServerListDialog : Gtk.Dialog {
	private enum Response {
		EDIT,
	    REFRESH,
		NEW
	}

	public ServerListDialog(ZMQ.Socket sock) {
		this.title = "Server List";

		Gtk.Box content = get_content_area() as Gtk.Box;
		content.pack_start(new ServerList(protocol.server.list(sock)), false, true, 0);

		add_button("_New", Response.NEW);
		add_button("_Edit", Response.EDIT);
		add_button("_Refresh", Response.EDIT);
		add_button("_Close", Gtk.ResponseType.CLOSE);

		this.response.connect((source, id) => {
				switch (id) {
				case Response.NEW: {
					string[] s = new string[5]; // host, port, nick, ident, real
					(new ServerListEditDialog(s)).run();
					stdout.printf("response: %s\n", s[0]);
					break;
				}
				case Response.EDIT: {
					new ServerListEditDialog(null);
					break;
				}
				case Response.REFRESH: {
					break;
				}
				case Gtk.ResponseType.CLOSE: {
					this.destroy();
					break;
				}
				}
			});
	}
}

// TODO: there is probably a nicer and more abstract way to do this
public class ServerListEditDialog : Gtk.Dialog {
	public ServerListEditDialog(string[] ss) {
		this.title = "Edit IRC Server";

		Gtk.Box content = get_content_area() as Gtk.Box;
		Gtk.Grid grid = new Gtk.Grid();

		var host_entry = new Gtk.Entry();
		var port_entry = new Gtk.Entry();
		var nick_entry = new Gtk.Entry();
		var ident_entry = new Gtk.Entry();
		var real_entry = new Gtk.Entry();

		// TODO: fix label alignment
		grid.attach(host_entry, 1, 0);
		grid.attach_next_to(new Gtk.Label("Host"), host_entry, Gtk.PositionType.LEFT);
		grid.attach(port_entry, 1, 1);
		grid.attach_next_to(new Gtk.Label("Port"), port_entry, Gtk.PositionType.LEFT);
		grid.attach(nick_entry, 1, 2);
		grid.attach_next_to(new Gtk.Label("Nickname"), nick_entry, Gtk.PositionType.LEFT);
		grid.attach(ident_entry, 1, 3);
		grid.attach_next_to(new Gtk.Label("Ident"), ident_entry, Gtk.PositionType.LEFT);
		grid.attach(real_entry, 1, 4);
		grid.attach_next_to(new Gtk.Label("Real name"), real_entry, Gtk.PositionType.LEFT);

		content.pack_start(grid);

		add_button("_Cancel", Gtk.ResponseType.REJECT);
		add_button("_Accept", Gtk.ResponseType.ACCEPT);

		this.response.connect((source, id) => {
				switch (id) {
				case Gtk.ResponseType.REJECT: {
					this.destroy();
					break;
				}
				case Gtk.ResponseType.ACCEPT: {
					// dup() so they won't get freed on widget destruction
					ss[0] = host_entry.get_text().dup();
					ss[1] = port_entry.get_text().dup();
					ss[2] = nick_entry.get_text().dup();
					ss[3] = ident_entry.get_text().dup();
					ss[4] = real_entry.get_text().dup();
					this.destroy();
					break;
				}
				}
			});

		this.show_all();
	}
}