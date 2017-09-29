// compile: valac -g --save-temps --thread --Xcc=-lzmq --pkg gtk+-3.0 --pkg json-glib-1.0 rschatc.vala zmq.vapi  && ./rschatc
using Gtk;
using ZMQ;

extern void exit(int exit_code);

//TextBuffer buffer;
//TextView text;
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
			this.nick = JSON.get_string(Json.Path.query("$.nick", node));
			this.ident = JSON.get_string(Json.Path.query("$.ident", node));
			this.real = JSON.get_string(Json.Path.query("$.real", node));
			
			foreach (Json.Node n in JSON.get_array(Json.Path.query("$.channels", node)).get_elements()) {
				channels.append(n.get_string());
			}
		} catch {
			exit(-1);
		}
	}
}

// GTK objects
public class IRCWindow : Gtk.Bin {
	private unowned ZMQ.Socket socket;
	public string recipient;

	public TextView view;
	public Entry entry;

	public IRCWindow(ZMQ.Socket sock, string recipient) {
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
//						var s = JOIN.serialize(t[6:t.length]);
						var s = (new Msg(new None<Prefix>(),
										 "JOIN",
                                         {t[6:t.length]})).serialize();
						var msg = ZMQ.Msg.with_data(s.data, free);
						msg.send(this.socket, 0);
						
					}

					this.entry.set_text("");
					return;
				} else {
//					var s = PRIVMSG.serialize(this.recipient, t);
					var s = (new Msg(new None<Prefix>(),
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
		if (m.prefix is Some<Prefix>) {
			var prefix_ = (m.prefix as Some<Prefix>).data;
			if (prefix_.discriminant) {
				stdout.printf("msg: prefix: %s %s %s\n", prefix_.nick, prefix_.ident, prefix_.host);
			} else {
				stdout.printf("msg: prefix: server: %s\n", prefix_.server);
			}
		}
		stdout.printf("msg: command=%s\n", m.command);
		foreach (string q in m.parameters) {
			stdout.printf("msg: param: %s\n", q);
		}
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
    window.title = "IRC";
    window.border_width = 10;
    window.window_position = WindowPosition.CENTER;
    window.set_default_size(350, 70);
    window.destroy.connect(Gtk.main_quit);

	pane_h = new Gtk.Paned(Gtk.Orientation.HORIZONTAL);
	pane_h.set_wide_handle(true);
	pane_h.add(tree);

	var sock_pair = ZMQ.Socket.create(ctx, ZMQ.SocketType.PAIR);
	sock_pair.bind("inproc://msg");
	stdout.printf("before sync call\n");
	irc_ctx = zmq_sync(sock_pair);
	stdout.printf("past sync call, %s\n", irc_ctx.channels.nth_data(0));

	//ZMQ.Msg().recv(sock_pair, 0);
    

	store.append(out tree_root, null);
	store.set(tree_root, 0, "localhost", -1);
	foreach (string c in irc_ctx.channels) {
		var win = new IRCWindow(sock_pair, c);
		windows.insert(c, win);
		store.append(out server, tree_root);
		store.set(server, 0, c, -1);
	}

	tree.expand_all();
	last = windows.lookup(irc_ctx.channels.first().data);
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
//	ZMQ.Msg().send(sock_pair, 0);
    window.add(pane_h);
	GLib.Idle.add_full(GLib.Priority.DEFAULT_IDLE, () => {
			var n = queue.try_pop();
			if (n != null) { 
				if (n is Left) {
					var ircmsg = (n as Left<Msg, Context>).left;
					string recp;
					var recp_c = ircmsg.recipient();
					if (recp_c is None) {
						return true;
						recp = "localhost";
					} else {
						recp = (recp_c as Some<string>).data;
					}
					var v = windows.lookup(recp);

					if (v == null) {
						var ircwindow = new IRCWindow(sock_pair, recp);
					
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
							var next = new IRCWindow(sock_pair, c);
							windows.insert(c, next);
							store.append(out server, tree_root);
							store.set(server, 0, c, -1);
						}
					}
				}
			}

			return true;
		});
    window.show_all();

    Gtk.main();
}