class_name GSBrowserA2sClient
extends GSBrowserQuery

## One A2S query in flight, pumped the same way [GSBrowserDqpClient] is.
##
## Asks [code]A2S_INFO[/code], and optionally [code]A2S_PLAYER[/code] after it. Both
## are challenged — [code]A2S_INFO[/code] gained a challenge in 2020 after years of
## being a reflection amplifier — so the exchange is:
##
## [codeblock]
## A2S_INFO                 ->
##                          <-  'A' challenge      (or 'I' from an old server)
## A2S_INFO with challenge  ->
##                          <-  'I' info
## [/codeblock]
##
## A server old enough not to challenge answers the first request, which is why the
## first one is sent without one and both replies are handled.

enum State { IDLE, INFO, PLAYERS, DONE }

## Ask for the roster after the info. One more round trip per server, so a browser
## leaves it off for a list and turns it on for the server a player clicked.
var want_players: bool = false

var retries: int = 1

var state: State = State.IDLE

var _socket: PacketPeerUDP = null
var _challenge: int = GSBrowserA2s.NO_CHALLENGE
var _deadline: int = 0
var _sent_at: int = 0
var _attempts_left: int = 0
var _info: Dictionary = {}
var _players: Array = []
var _split: Array[PackedByteArray] = []
var _split_id: int = -1


func query_name() -> StringName:
	return &"a2s"


func begin() -> GSResult:
	if not GSPlatform.has_udp():
		return _finish(GSResult.fail(
			GSError.CODE_UNSUPPORTED,
			"A2S is UDP only and this platform has none. A browser build cannot "
			+ "speak it at any price."
		))

	if target == null or target.address == "":
		return _finish(GSResult.fail(GSError.CODE_INVALID, "No address to query."))

	# A name is looked up first; see GSBrowserQuery's "Name lookup".
	var looked := lookup_begin()
	if not looked.ok:
		return _finish(looked)
	if str(looked.value) == "":
		return GSResult.success(self)

	return _open(str(looked.value))


func _open(ip: String) -> GSResult:
	_socket = PacketPeerUDP.new()
	var err := _socket.connect_to_host(ip, target.effective_query_port())
	if err != OK:
		return _finish(GSResult.failure(
			GSError.from_engine(err, "could not open a socket to %s" % target.key())
		))

	_attempts_left = maxi(0, retries)
	_send_info()

	return GSResult.success(self)


func poll(now_ms: int) -> bool:
	if state == State.DONE:
		return true
	if lookup_pending():
		var looked := lookup_poll(now_ms)
		if not looked.ok:
			_finish(looked)
			return true
		if str(looked.value) == "":
			return false
		_open(str(looked.value))
		return state == State.DONE
	if state == State.IDLE or _socket == null:
		return false

	while _socket.get_available_packet_count() > 0:
		if _handle(_socket.get_packet(), now_ms):
			return true

	if now_ms >= _deadline:
		if _attempts_left > 0:
			_attempts_left -= 1
			if state == State.INFO:
				_send_info()
			else:
				_send_players()
			return false

		if state == State.PLAYERS and not _info.is_empty():
			# The roster is an extra. A server that answered the info and then went
			# quiet is still a server worth listing, and reporting it offline because
			# the second request was dropped would be wrong about the first.
			_finish(GSResult.success({"info": _info, "players": _players}))
			return true

		_finish(GSResult.fail(
			GSError.CODE_TIMEOUT, "The server did not answer.", target.key()
		))
		return true

	return false


func close() -> void:
	lookup_cancel()
	if _socket != null:
		_socket.close()
		_socket = null


func _handle(data: PackedByteArray, now_ms: int) -> bool:
	if GSBrowserA2s.is_split(data):
		return _handle_split(data, now_ms)

	if not GSBrowserA2s.is_single(data):
		return false

	return _handle_single(data, now_ms)


func _handle_split(data: PackedByteArray, now_ms: int) -> bool:
	var head := GSBrowserA2s.parse_split_header(data)
	if head.is_empty():
		return false

	var id := int(head["id"])
	if _split_id < 0:
		_split_id = id
	elif id != _split_id:
		return false

	for held in _split:
		if held.decode_u8(9) == data.decode_u8(9):
			return false

	_split.append(data)

	if _split.size() < int(head["total"]):
		return false

	var joined := GSBrowserA2s.reassemble_split(_split)
	_split.clear()
	_split_id = -1

	if not joined.ok:
		_finish(joined)
		return true

	return _handle_single(joined.value, now_ms)


func _handle_single(data: PackedByteArray, now_ms: int) -> bool:
	var type := GSBrowserA2s.response_type(data)

	if type == GSBrowserA2s.RESPONSE_CHALLENGE:
		_challenge = GSBrowserA2s.challenge_of(data)
		_attempts_left = maxi(0, retries)
		if state == State.INFO:
			_send_info()
		else:
			_send_players()
		return false

	if type == GSBrowserA2s.RESPONSE_INFO:
		if ping_ms < 0:
			ping_ms = maxi(0, now_ms - _sent_at)

		var parsed := GSBrowserA2s.parse_info(data)
		if not parsed.ok:
			_finish(parsed)
			return true

		_info = parsed.value

		if want_players and _challenge != GSBrowserA2s.NO_CHALLENGE:
			_attempts_left = maxi(0, retries)
			_send_players()
			return false

		if want_players:
			# No challenge in hand, because this server answered the first INFO
			# without issuing one. A2S_PLAYER still needs one, so it is asked for
			# explicitly rather than being sent a guess.
			_attempts_left = maxi(0, retries)
			_send_players()
			return false

		_finish(GSResult.success({"info": _info, "players": _players}))
		return true

	if type == GSBrowserA2s.RESPONSE_PLAYER:
		var rows := GSBrowserA2s.parse_players(data)
		if rows.ok:
			_players = rows.value
		_finish(GSResult.success({"info": _info, "players": _players}))
		return true

	return false


func _send_info() -> void:
	state = State.INFO
	_sent_at = Time.get_ticks_msec()
	_deadline = _sent_at + timeout_ms
	_socket.put_packet(GSBrowserA2s.build_info(_challenge))


func _send_players() -> void:
	state = State.PLAYERS
	_sent_at = Time.get_ticks_msec()
	_deadline = _sent_at + timeout_ms
	_socket.put_packet(GSBrowserA2s.build_player(_challenge))


func _finish(res: GSResult) -> GSResult:
	state = State.DONE
	return finish(res)
