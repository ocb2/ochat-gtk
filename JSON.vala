namespace JSON {
	// TODO: make proper errors
	errordomain Error {
		NO_SUCH_KEY,
		TYPE_MISMATCH,
		MALFORMED,
		EMPTY,
		NOT_SINGLETON
	}

	// simple helpers to help with error handling
	Json.Array get_array(Json.Node node) throws Error {
		Json.Array ar = node.get_array();

		if (ar == null) {
			throw new Error.TYPE_MISMATCH(node.type_name());
		} else {
			return ar;
		}
	}

	int64 get_int(Json.Node node) throws Error {
		string v = node.type_name();
		stdout.printf("tyype name: %s\n", v);

		if (v == "int") {
			return node.get_int();
		} else {
			throw new Error.TYPE_MISMATCH(v);
		}
	}

	string get_string(Json.Node node) throws Error {
		string v = node.get_string();

		if (v == null) {
			throw new Error.TYPE_MISMATCH(node.type_name());
		} else {
			return v;
		}
	}

	Json.Node query_singleton(string query, Json.Node node) throws Error {
		try {
			var ar = get_array(Json.Path.query(query, node));
			if (ar.get_length() < 1) {
				throw new Error.EMPTY("singleton");
			} else if (ar.get_length() > 1) {
				throw new Error.NOT_SINGLETON("singleton");
			}
			return ar.get_element(0);
		} catch (GLib.Error e) {
			throw new Error.EMPTY("singleton");
		}
	}

	string query_string(string query, Json.Node node) throws Error {
		return get_string(query_singleton(query, node));
	}

	int64 query_int(string query, Json.Node node) throws Error {
		return get_int(query_singleton(query, node));
	}
}