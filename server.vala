
class CandidateList : Object
{
	public struct Candidate
	{
		string foundation;
		uint priority;
		string ipaddr;
		uint port;
		uint type;
	}

	// List<Candidate?> candidates = new List<Candidate?> ();
	string data;

	public CandidateList ()
	{
	}

	public void load (string json)
	{
		data = json;
		/*var parser = new Json.Parser ();
		parser.load_from_data (json);

		var root = parser.get_root ();
		if (root == null)
			throw new IOError.INVALID_DATA ("Invalid candidate");

		var list = root.get_array ();

		list.foreach_element ((array, index, node) => {
			var object = node.get_object ();
			Candidate c = {
				object.get_string_member ("foundation"),
				(uint) object.get_int_member ("priority"),
				object.get_string_member ("ipaddr"),
				(uint) object.get_int_member ("port"),
				(uint) object.get_int_member ("type")
			};
			candidates.append (c);
		});*/
	}

	public string toJSON()
	{
		/*var list = "";
		foreach (var c in candidates) {
			list += "{\"foundation\":\"%s\",\"priority\":%u,\"ipaddr\":\"%s\",\"port\":%u,\"type\":\"%u\"}"
				.printf (c.foundation, c.priority, c.ipaddr, c.port, c.type);
		}
		return "[" + list + "]";*/
		return data;
	}
}

public class Server : Soup.Server
{
	HashTable<string,Session?> sessions =
		new HashTable<string,Session?> (str_hash, str_equal);

	struct Session
	{
		Soup.Message queued_message;
		CandidateList candidate_list;
	}

	public Server ()
	{
		Object (port: 8000);

		add_handler ("/negotiate/create", negotiate_create);
		add_handler ("/negotiate/join", negotiate_join);
	}

	public override void request_finished (Soup.Message msg, Soup.ClientContext context)
	{
		print ("REQUEST FINISHED\n");
		base.request_finished (msg, context);
	}

	public override void request_aborted (Soup.Message msg, Soup.ClientContext context)
	{
		print ("REQUEST ABORT\n");
		foreach (var id in sessions.get_keys ()) {
			if (sessions[id].queued_message == msg) {
				print ("Session request for id `%s` aborted.\n", id);
				sessions.remove (id);
				break;
			}
		}

		base.request_aborted (msg, context);
	}

	void negotiate_create (Soup.Server server, Soup.Message msg, string path,
			HashTable<string,string>? query, Soup.ClientContext client)
	{
		string id = "";

		if (query == null || !("id" in query) || (id = query["id"]) == null) {
			msg.set_status_full (400, "ID parameter missing.");
			return;
		}

		var list = new CandidateList ();
		list.load ((string) msg.request_body.data);

		sessions[id] = {
			msg,
			list
		};
		print ("Created session for id `%s`\n", id);

		msg.finished.connect (() => { print ("FINISHED\n"); });
		msg.network_event.connect ((evt) => { print ("EVENT %s\n", evt.to_string ()); });
		pause_message (msg);
	}

	void negotiate_join (Soup.Server server, Soup.Message msg, string path,
			HashTable<string,string>? query, Soup.ClientContext client)
	{
		if (query == null || !("id" in query)) {
			msg.set_status_full (400, "ID parameter missing.");
			return;
		}

		var id = query["id"];
		print ("Received request for id `%s`\n", id);

		if (!(id in sessions)) {
			msg.set_status_full (404, "Requested ID is not offering a connection.");
			return;
		}

		var session = sessions[id];

		session.queued_message.status_code = 200;
		session.queued_message.set_response ("application/json",
				Soup.MemoryUse.COPY, msg.request_body.data);
		unpause_message (session.queued_message);

		sessions.remove (id);

		msg.status_code = 200;
		msg.set_response ("application/json", Soup.MemoryUse.COPY,
				session.candidate_list.toJSON ().data);
	}
}

void main (string[] args)
{
	var server = new Server ();
	server.run ();
}

