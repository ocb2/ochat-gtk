using Gtk;
using ZMQ;

extern void exit(int exit_code);

ZMQ.Context ctx;
Context irc_ctx;
HashTable<string, IRCWindow> windows;
IRCWindow last;
TreeView tree;
TreeStore store;
Paned pane_h;
TreeIter tree_root;
TreeIter server;
AsyncQueue<Sum<Msg,Context>> queue;

public interface Sum<L,R> : Object {}

public class Left<L,R> : Sum<L,R>, Object {
	public L left;
	public Left(L l) { this.left = l; }
}

public class Right<L,R> : Sum<L,R>, Object {
	public R right;
	public Right(R r) { this.right = r; }
}

// IRC objects
public class Context : Object {
	public string nick;
	public string ident;
	public string real;

	public List<string> channels;

	public Context.from_json(Json.Node node) throws JSON.Error {
		try {
			this.nick = JSON.query_string("$.nick", node);
			this.ident = JSON.query_string("$.ident", node);
			this.real = JSON.query_string("$.realname", node);
			
			foreach (Json.Node n in JSON.get_array(Json.Path.query("$.channels.*", node)).get_elements()) {
				var n_ = JSON.get_array(n);
				// no, I don't know why this is necessary either
				// TODO: file bug report
				if (n_.get_length() == 0) { break; }
				stderr.printf("Malformed context:\n%s\n%s\n", Json.to_string(node, true), Json.to_string(n, true));
				this.channels.append(JSON.get_string(n_.get_element(0)));
			}
		} catch {
			stderr.printf("Malformed context:\n%s\n", Json.to_string(node, true));
			exit(-1);
		    throw new JSON.Error.MALFORMED("context");
		}
	}
}

// GTK objects
public class IRCWindow : Gtk.Bin {
	private unowned ZMQ.Socket socket;
	public string server;
	public string recipient;

	public TextView view;
	public Entry entry;

	public IRCWindow(ZMQ.Socket sock, string server, string recipient) {
		this.server = server;
		this.recipient = recipient;
		this.socket = sock;

		var pane_t = new Gtk.Paned(Gtk.Orientation.VERTICAL);
		var pane_e = new Gtk.Paned(Gtk.Orientation.VERTICAL);

		var text_scroll = new ScrolledWindow(null, null);
		var topic = new Entry();

		this.entry = new Entry();
		this.view = new TextView();

		this.view.editable = false;
		this.view.cursor_visible = false;
		this.view.set_wrap_mode(Gtk.WrapMode.WORD_CHAR);
	    
		this.entry.activate.connect(() => {
				var t = this.entry.get_text();

				if (t[0] == '/') {
					// TODO: slightly more robust parsing logic...
					if (t[1:5] == "join") {
						var s = (new Msg(this.server,
										 new None<Prefix>(),
										 "JOIN",
                                         {t[6:t.length]})).serialize();
						var msg = ZMQ.Msg.with_data(s.data, free);
						msg.send(this.socket, 0);
						
					}

					this.entry.set_text("");
					return;
				} else {
					var s = (new Msg(this.server,
									 new None<Prefix>(),
									 "PRIVMSG",
					{this.recipient,t})).serialize();
					
					var msg = ZMQ.Msg.with_data(s.data, free);
					msg.send(this.socket, 0);
					this.entry.set_text("");
				
				
					var q = irc_ctx.nick + ": " + t + "\n";

					// TODO: subclass buffer and make this method scroll_to_end
					TextIter end;
					var buffer = this.view.get_buffer();
					buffer.get_end_iter(out end);
					buffer.insert(ref end, q, q.length);
					buffer.get_end_iter(out end);
					TextMark mark = buffer.create_mark(null, end, false);
					view.scroll_to_mark(mark, 0, false, 0, 0);
				}
			});

		pane_t.add(topic);
		pane_t.add(pane_e);

		text_scroll.add(view);
		pane_e.pack1(text_scroll, true, false);
		pane_e.pack2(entry, false, true);
		this.add(pane_t);
		this.show_all();
	}

	public void interpret(Msg m) {
		string s;
		switch (m.command) {
		case "JOIN": {
			s = (m.prefix as Some<Prefix>).data.nick +
			": " +
			m.parameters[0] +
			"\n";
			break;
		}
		case "PART": {
			s = "part: " +
			(m.prefix as Some<Prefix>).data.nick +
			" from " +
			m.parameters[0] +
			": " +
			m.parameters[1] +
			"\n";
			break;
		}
		case "PRIVMSG": {
			s = (m.prefix as Some<Prefix>).data.nick +
			": " +
			m.parameters[1] +
			"\n";
			break;
		}
		default: { s = ""; break; }
		}
		var buffer = this.view.get_buffer();

		TextIter end;
		buffer.get_end_iter(out end);
		buffer.insert(ref end, s, s.length);
		buffer.get_end_iter(out end);
		TextMark mark = buffer.create_mark(null, end, false);
		view.scroll_to_mark(mark, 0, false, 0, 0);
	}
}

// TODO: organize this into sections
void main (string[] args) {
    ctx = new ZMQ.Context(1);
	new Thread<void*>(null, zmq);

	windows = new HashTable<string, IRCWindow>(str_hash, str_equal);
	queue = new AsyncQueue<Sum<Msg,Context>>();
	
    Gtk.init(ref args);
	
	tree = new TreeView();
	store = new TreeStore(1, typeof(string));
	tree_root = TreeIter();
	server = TreeIter();

	tree.set_model(store);
	tree.insert_column_with_attributes(-1, null, new CellRendererText(), "text", 0, null);
	tree.set_headers_visible(false);

    var window = new Window();
    window.title = "ochat";
    window.border_width = 10;
    window.window_position = WindowPosition.CENTER;
    window.set_default_size(350, 70);
    window.destroy.connect(Gtk.main_quit);

	// message bar
	var box_top = new Gtk.Box(Gtk.Orientation.VERTICAL, 0);
	var menu_bar = new Gtk.MenuBar();
	box_top.pack_start(menu_bar, false, false, 0);
	window.add(box_top);

	Gtk.MenuItem menu_item_file = new Gtk.MenuItem.with_mnemonic("_File");
	menu_bar.add(menu_item_file);

	Gtk.Menu menu_file = new Gtk.Menu();
	menu_item_file.set_submenu(menu_file);

	Gtk.MenuItem menu_item_file_exit = new Gtk.MenuItem.with_mnemonic("E_xit");
	menu_file.add(menu_item_file_exit);
	menu_item_file_exit.activate.connect(() => { Gtk.main_quit(); });

	Gtk.MenuItem menu_item_server = new Gtk.MenuItem.with_mnemonic("_Server");
	menu_bar.add(menu_item_server);

	Gtk.Menu menu_server = new Gtk.Menu();
	menu_item_server.set_submenu(menu_server);
	var sock_pair = ZMQ.Socket.create(ctx, ZMQ.SocketType.PAIR);
	sock_pair.bind("inproc://msg");

	Gtk.MenuItem menu_item_server_list = new Gtk.MenuItem.with_mnemonic("_List");
	menu_server.add(menu_item_server_list);
	menu_item_server_list.activate.connect(() => {
			var dialog = new ServerListDialog(sock_pair);
			dialog.show_all();
		});

	pane_h = new Gtk.Paned(Gtk.Orientation.HORIZONTAL);
	pane_h.set_wide_handle(true);
	pane_h.add(tree);

	irc_ctx = protocol.sync(sock_pair, "localhost");
	var js = new Msg("localhost",
					 new None<Prefix>(),
					 "JOIN",
					 {"#channel"}).serialize();
	var msg = ZMQ.Msg.with_data(js.data, free);
	msg.send(sock_pair, 0);
	msg = ZMQ.Msg();
	msg.recv(sock_pair);

	store.append(out tree_root, null);
	store.set(tree_root, 0, "localhost", -1);
	foreach (string c in irc_ctx.channels) {
		var win = new IRCWindow(sock_pair, "localhost", c);
		if (c == null) { stderr.printf("seriously?\n, %u", irc_ctx.channels.length());  }
		windows.insert(c, win);
		store.append(out server, tree_root);
		store.set(server, 0, c, -1);
	}

	tree.expand_all();
	if (irc_ctx.channels.length() > 0) {
		last = windows.lookup(irc_ctx.channels.first().data);
	}
	pane_h.add(last);
	tree.cursor_changed.connect(() => {
			Gtk.TreeModel model;
			Gtk.TreeIter iter;
			string s;
			tree.get_selection().get_selected(out model, out iter);
			model.get(iter, 0, out s);
			var next = windows.lookup(s);
			if (next != null) {
				pane_h.remove(last);
				pane_h.add(next);
				last = next;
			}
		});

	GLib.Idle.add_full(GLib.Priority.DEFAULT_IDLE, () => {
			var n = queue.try_pop();

			if (n != null) { 
				if (n is Left) {
					var ircmsg = (n as Left<Msg, Context>).left;
					string recp;
					var recp_c = ircmsg.recipient();
					if (recp_c is None) {
						return true;
					} else {
						recp = (recp_c as Some<string>).data;
					}
					var v = windows.lookup(recp);

					if (v == null) {
						var ircwindow = new IRCWindow(sock_pair, "localhost", recp);
					
						windows.insert(recp, ircwindow);
						store.append(out server, tree_root);
						store.set(server, 0, recp, -1);
						ircwindow.interpret(ircmsg);
					} else {
						v.interpret(ircmsg);
					}
				} else {
					var new_ctx = (n as Right<Msg, Context>).right;
					foreach (string c in new_ctx.channels) {
						if (irc_ctx.channels.find(c) == null) {
						} else {
							var next = new IRCWindow(sock_pair, "localhost", c);
							windows.insert(c, next);
							store.append(out server, tree_root);
							store.set(server, 0, c, -1);
						}
					}
				}
			}

			return true;
		});

    box_top.pack_start(pane_h, true, true, 0);
    window.show_all();
    Gtk.main();
}