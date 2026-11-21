class_name GSBrowserWsClient
extends GSBrowserQuery

## DQP over a WebSocket: the only query a browser build can make.
##
## A web page cannot open a UDP socket, so it can never speak A2S at any price and
## cannot speak DQP's UDP form either. GameSpice Server serves the same protocol as plain
## JSON text frames over TCP for exactly this: send the request body, receive the
## response body, no binary header and no challenge.
##
## [b]There is no challenge here and that is not an oversight.[/b] The cookie exists
## to prove a UDP source address is real. A WebSocket has completed a TCP handshake
## and an HTTP upgrade, so the transport already proved it, and the reply travels
## back down the same connection where it cannot be aimed at anybody else.
##
## [b]On the scheme.[/b] This does not upgrade [code]ws://[/code] to
## [code]wss://[/code] on a secure page. `GSWeb.is_secure_context()` is not "the page
## is HTTPS" — a browser treats [code]http://localhost[/code] as a trustworthy origin,
## so it is true on a plain HTTP page — and GameSpice Core's transport once upgraded every
## development page's socket and failed against a server with no certificate.
## [method GSWeb.is_https_page] is the right question: on such a page [code]ws://[/code]
## is upgraded to [code]wss://[/code] (a server without TLS then fails quietly instead of
## tripping the page's CSP), and a loopback endpoint is skipped: no visitor's 127.0.0.1
## is the server.

enum State { IDLE, CONNECTING, WAITING, DONE }

var sections: PackedStringArray = PackedStringArray(["info"])
var if_rev: int = 0

var state: State = State.IDLE

var _peer: WebSocketPeer = null
var _deadline: int = 0
var _sent_at: int = 0
var _sent: bool = false


## The URL this will open: the target's own, or one derived from its address.
func query_name() -> StringName:
	return &"dqp-ws"


func url() -> String:
	if target == null:
		return ""
	var raw := target.websocket_url
	if raw == "":
		raw = "ws://%s:%d" % [target.address, target.effective_query_port()]
	return page_url(raw, GSWeb.is_https_page())


## [param raw] as a page may open it: ws:// becomes wss:// on an HTTPS page, and a
## loopback host there yields "" (not queryable).
static func page_url(raw: String, https_page: bool) -> String:
	if not https_page or not raw.begins_with("ws://"):
		return raw
	var rest := raw.substr(5)
	var host := rest.split("/")[0].rsplit(":", true, 1)[0].trim_prefix("[").trim_suffix("]")
	if host == "localhost" or host == "::1" or host.begins_with("127.") or host == "0.0.0.0":
		return ""
	return "wss://" + rest


func begin() -> GSResult:
	if not GSPlatform.has_websocket():
		return _finish(GSResult.fail(
			GSError.CODE_UNSUPPORTED, "This platform has no WebSocket."
		))

	var address := url()
	if address == "":
		return _finish(GSResult.fail(GSError.CODE_INVALID, "No address to query (or loopback on an HTTPS page)."))

	_peer = WebSocketPeer.new()
	var err := _peer.connect_to_url(address)
	if err != OK:
		return _finish(GSResult.failure(
			GSError.from_engine(err, "could not open %s" % address)
		))

	state = State.CONNECTING
	_sent_at = Time.get_ticks_msec()
	_deadline = _sent_at + timeout_ms

	return GSResult.success(self)


func poll(now_ms: int) -> bool:
	if state == State.DONE:
		return true
	if state == State.IDLE or _peer == null:
		return false

	_peer.poll()

	match _peer.get_ready_state():
		WebSocketPeer.STATE_OPEN:
			if not _sent:
				_send()

			while _peer.get_available_packet_count() > 0:
				var text := _peer.get_packet().get_string_from_utf8()
				var parsed: Variant = JSON.parse_string(text)

				if typeof(parsed) != TYPE_DICTIONARY:
					_finish(GSResult.fail(
						GSError.CODE_PARSE, "The response was not a JSON object."
					))
					return true

				var body: Dictionary = parsed
				ping_ms = maxi(0, now_ms - _sent_at)

				if body.has("error"):
					_finish(GSBrowserDqp.error_from_body(body))
					return true

				_finish(GSResult.success(body))
				return true

		WebSocketPeer.STATE_CLOSED:
			_finish(GSResult.fail(
				GSError.CODE_NETWORK,
				"The connection closed before an answer arrived.",
				"code %d" % _peer.get_close_code()
			))
			return true

	if now_ms >= _deadline:
		_finish(GSResult.fail(
			GSError.CODE_TIMEOUT, "The server did not answer.", url()
		))
		return true

	return false


func close() -> void:
	if _peer != null:
		_peer.close()
		_peer = null


func _send() -> void:
	var body := {"sections": Array(sections)}
	if if_rev > 0:
		body["if_rev"] = if_rev

	_sent = true
	_sent_at = Time.get_ticks_msec()
	_peer.send_text(JSON.stringify(body))


func _finish(res: GSResult) -> GSResult:
	state = State.DONE
	return finish(res)
