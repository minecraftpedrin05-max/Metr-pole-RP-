extends Node
# Ponto de entrada do servidor dedicado (sem tela). Abre o servidor WebSocket e fica rodando.
# A porta vem da variavel PORT (o Railway define sozinho); sem ela usa 7777.


func _ready():
	var ok = Rede.servidor_dedicado()
	if ok:
		print("[Servidor] rodando. Servidores (salas): ", Servidor.SALAS, " | maximo por sala: ", Servidor.MAX_POR_SALA)
	else:
		print("[Servidor] FALHOU ao abrir a porta")
		get_tree().quit(1)
