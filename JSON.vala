namespace JSON {
	errordomain Error {
		NO_SUCH_KEY,
		TYPE_MISMATCH,
		MALFORMED
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

	string get_string(Json.Node node) throws Error {
		string v = node.get_string();
		if (v == null) {
			throw new Error.TYPE_MISMATCH(node.type_name());
		} else {
			return v;
		}
	}
}