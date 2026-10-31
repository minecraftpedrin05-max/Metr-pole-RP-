extends Node
# MTP COINS: busca no site de resgate (servico "metropole-coins") os codigos resgatados
# e credita os coins nas contas do servidor dedicado. So roda no servidor dedicado (Railway).
# Variaveis de ambiente do servidor do jogo:
#   COINS_URL    ex.: https://metropole-coins.up.railway.app   (ou http://metropole-coins.railway.internal:3000)
#   COINS_TOKEN  o mesmo valor de JOGO_TOKEN do servico de coins

const INTERVALO = 8.0

var url = ""
var token = ""
var http = null
var t = 0.0
var fase = ""          # "" = livre, "buscar", "confirmar"
var lote_ids = []
var ligado = false
var erros_seguidos = 0


func _ready():
	url = OS.get_environment("COINS_URL").strip_edges().rstrip("/")
	token = OS.get_environment("COINS_TOKEN").strip_edges()
	if url == "" or token == "":
		print("[coins] COINS_URL/COINS_TOKEN nao definidos: resgate de MTP COINS desligado neste servidor.")
		set_process(false)
		return
	http = HTTPRequest.new()
	http.timeout = 10.0
	add_child(http)
	http.request_completed.connect(_ao_responder)
	ligado = true
	t = INTERVALO - 1.0
	print("[coins] ligado em ", url)


func _process(delta):
	if not ligado or fase != "":
		return
	t += delta
	if t < INTERVALO:
		return
	t = 0.0
	fase = "buscar"
	var e = http.request(url + "/api/jogo/pendentes", ["Authorization: Bearer " + token])
	if e != OK:
		_falhou("pedido recusado (" + str(e) + ")")


func _falhou(motivo):
	fase = ""
	erros_seguidos += 1
	# so avisa na 1a falha e depois de tempos em tempos, para nao encher o log
	if erros_seguidos == 1 or erros_seguidos % 40 == 0:
		print("[coins] falha ao falar com o site de coins: ", motivo)


func _ao_responder(resultado, codigo, _cabecalhos, corpo):
	if resultado != HTTPRequest.RESULT_SUCCESS or codigo != 200:
		_falhou("resultado " + str(resultado) + " http " + str(codigo))
		return
	if erros_seguidos > 0:
		print("[coins] conexao com o site de coins restabelecida")
	erros_seguidos = 0
	var j = JSON.new()
	if j.parse(corpo.get_string_from_utf8()) != OK or not (j.data is Dictionary):
		fase = ""
		return
	if fase == "buscar":
		var lista = j.data.get("pendentes", [])
		if not (lista is Array) or lista.is_empty():
			fase = ""
			return
		lote_ids = []
		for r in lista:
			if not (r is Dictionary):
				continue
			if Servidor.coins_creditar(str(r.get("codigo", "")), str(r.get("conta", "")), int(r.get("coins", 0))):
				lote_ids.append(int(r.get("id", 0)))
		if lote_ids.is_empty():
			fase = ""
			return
		fase = "confirmar"
		var corpo_json = JSON.stringify({"ids": lote_ids})
		var e = http.request(url + "/api/jogo/confirmar", ["Authorization: Bearer " + token, "Content-Type: application/json"], HTTPClient.METHOD_POST, corpo_json)
		if e != OK:
			_falhou("confirmacao recusada (" + str(e) + ")")
	else:
		# se a confirmacao nao chegar, o site manda de novo e o servidor ignora (ja creditado)
		fase = ""
