
// TODO move stuff into a class, so that the global doesn't look as ugly
Nice.Agent agent;
uint stream_id;
MainLoop loop;

int main (string[] args)
{
	loop = new MainLoop ();
	var io_stdin = new IOChannel.unix_new (stdin.fileno ());

	if (args.length != 2 && args.length != 3)
		error ("Invalid arguments. Usage: [-l] <id>");

	var id = args.length == 3 ? args[2] : args[1];
	agent = new Nice.Agent (loop.get_context (), Nice.Compatibility.RFC5245);
	agent.stun_server = "74.125.136.127";
	agent.stun_server_port = 19302;
	agent.controlling_mode = args[1] == "-l";
	// agent.proxy_ip = "37.59.53.32";
	// agent.proxy_port = 8080;
	// agent.proxy_type = Nice.ProxyType.HTTP;

	agent.candidate_gathering_done.connect ((stream_id) => {
		unowned SList<Nice.Candidate> candidates = agent.get_local_candidates (stream_id, 1);
		var list = "";

		foreach (unowned Nice.Candidate c in candidates) {
			string ipaddr = "";
			c.addr.to_string (ipaddr);

			if (list.length > 0)
				list += ",";

			list += "{\"foundation\":\"%s\",\"priority\":%u,\"ipaddr\":\"%s\",\"port\":%u,\"type\":%u}"
				.printf ((string) c.foundation, c.priority, ipaddr, c.addr.get_port (), (uint) c.type);
		}

		string ufrag, password;
		agent.get_local_credentials (stream_id, out ufrag, out password);

		var data = "{\"ufrag\":\"%s\",\"password\":\"%s\",\"candidates\":[%s]}"
			.printf (ufrag, password, list);

		var session = new Soup.Session ();
		var msg = new Soup.Message ("GET", "http://cloud.tombeckmann.de:8002/negotiate/%s?id=%s"
				.printf (agent.controlling_mode ? "create" : "join", id));

		msg.finished.connect (() => {
			if (msg.status_code != 200) {
				error ("Negotiation failed: %u: %s\n", msg.status_code, msg.reason_phrase);
			}

			Json.Node root;

			try {
				var parser = new Json.Parser ();
				parser.load_from_data ((string) msg.response_body.data,
					(ssize_t) msg.response_body.length);
				root = parser.get_root ();
			} catch (Error e) {
				error ("Invalid candidate data sent: %s", e.message);
			}

			printerr ("RECEIVED: %s\n", (string) msg.response_body.data);
			var remote_candidates = new SList<Nice.Candidate> ();

			var main = root.get_object ();
			if (main == null)
				error ("Invalid negotiation response received");

			main.get_array_member ("candidates").foreach_element ((array, index, node) => {
				var object = node.get_object ();

				var candidate = new Nice.Candidate ((uint) object.get_int_member ("type"));
				candidate.component_id = 1;
				candidate.stream_id = stream_id;
				candidate.transport = Nice.CandidateTransport.UDP;
				candidate.foundation = (char[]) object.get_string_member ("foundation").data;
				candidate.priority = (uint) object.get_int_member ("priority");

				if (!candidate.addr.set_from_string (object.get_string_member ("ipaddr")))
					error ("Failed to parse remote addr: %s",
						object.get_string_member ("ipadr"));
				candidate.addr.set_port ((uint) object.get_int_member ("port"));

				remote_candidates.prepend ((owned) candidate);
			});

			if (!agent.set_remote_credentials (stream_id,
					main.get_string_member ("ufrag"),
					main.get_string_member ("password")))
				error ("Failed to set remote credentials.");

			if (agent.set_remote_candidates (stream_id, 1, remote_candidates) < 1)
				error ("Failed to set remote candidates.");
		});

		printerr ("Waiting for remote to connect ...\n");
		msg.set_request ("application/json", Soup.MemoryUse.COPY, data.data);
		session.send_message (msg);
	});
	agent.new_selected_pair.connect ((agent, stream_id, component_id,
				lfoundation, rfoundation) => {
		printerr ("SIGNAL: selected pair %s %s", lfoundation, rfoundation);
	});
	agent.component_state_changed.connect ((agent, stream_id, component_id, state) => {
		printerr ("state change: %s\n", state.to_string ());

		if (state == Nice.ComponentState.READY) {
			unowned Nice.Candidate local, remote;
			string local_ip = "", remote_ip = "";
			agent.get_selected_pair (stream_id, component_id, out local, out remote);

			local.addr.to_string (local_ip);
			remote.addr.to_string (remote_ip);

			printerr ("Negotiation complete: (local: [%s]:%u <-> remote: [%s]:%u)\n",
				local_ip, local.addr.get_port (), remote_ip, remote.addr.get_port ());

			io_stdin.add_watch (IOCondition.IN, read_stdin);
		} else if (state == Nice.ComponentState.FAILED) {
			error ("Failed to negotiate connection.");
		}
	});

	stream_id = agent.add_stream (1);
	if (stream_id == 0)
		error ("Failed to add stream");

	if (!agent.set_relay_info (stream_id, 1, "37.59.53.32", 3478, "tom", "mypw", Nice.RelayType.TCP))
		error ("Failed to set TURN server info.");

	agent.attach_recv (stream_id, 1, loop.get_context (),
			(agent, stream_id, component_id, len, buf) => {

		if (len == 1 && buf[0] == '\0')
			loop.quit ();

		print ("%.*s", len, buf);
	});

	if (!agent.gather_candidates (stream_id))
		error ("Failed to start gathering candidates");

	loop.run ();

	return 0;
}

bool read_stdin (IOChannel channel, IOCondition condition) {
	string line;
	size_t len;
	var status = IOStatus.NORMAL;

	try {
		status = channel.read_line (out line, out len, null);
	} catch (Error e) {
		warning ("Failed to read local data: %s", e.message);
		status = IOStatus.ERROR;
	}

	if (status != IOStatus.NORMAL) {
		agent.send (stream_id, 1, 1, "\0");
		loop.quit ();
	} else
		agent.send (stream_id, 1, line.length, line);

	return true;
}

