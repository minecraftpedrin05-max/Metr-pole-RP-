extends RefCounted
# Gerado a partir do modelo big_city (escala 1:1, 1 unidade = 1 metro). Nao muda o modelo.
const Y0 = -1.15
const SPAWN = Vector3(-150.0, -1.15, -150.0)
const SPAWN_YAW = 90.0
const LIMITE_MIN = Vector3(-1640.0, -80.0, -1660.0)
const LIMITE_MAX = Vector3(1340.0, 500.0, 1390.0)

const POIS = [
	{"id": "banco", "nome": "Banco", "tipo": "banco", "pos": Vector3(-155.0, -1.15, -193.0), "frente": Vector3(-1, 0, 0), "garagem": Vector3(-155.0, -1.15, -201.0)},
	{"id": "mercado", "nome": "Mercado", "tipo": "mercado", "pos": Vector3(-57.0, -1.15, -79.0), "frente": Vector3(-1, 0, 0), "garagem": Vector3(-65.0, -1.15, -78.0)},
	{"id": "roupas", "nome": "Loja de Roupas", "tipo": "roupas", "pos": Vector3(-160.0, -1.15, 5.0), "frente": Vector3(1, 0, 0), "garagem": Vector3(-152.0, -1.15, 5.0)},
	{"id": "posto", "nome": "Posto de Combustível", "tipo": "posto", "pos": Vector3(-315.0, -1.15, -122.0), "frente": Vector3(-1, 0, 0), "garagem": Vector3(-319.0, -1.15, -115.0)},
	{"id": "oficina", "nome": "Oficina", "tipo": "oficina", "pos": Vector3(-140.0, -1.15, -370.0), "frente": Vector3(-1, 0, 0), "garagem": Vector3(-148.0, -1.15, -370.0)},
	{"id": "concessionaria", "nome": "Concessionária", "tipo": "concessionaria", "pos": Vector3(78.0, -1.15, -127.0), "frente": Vector3(0, 0, -1), "garagem": Vector3(78.0, -1.15, -135.0)},
	{"id": "prefeitura", "nome": "Prefeitura", "tipo": "prefeitura", "pos": Vector3(-33.0, -1.15, 49.0), "frente": Vector3(0, 0, 1), "garagem": Vector3(-40.0, -1.15, 53.0)},
	{"id": "casa_1", "nome": "Casa 1", "tipo": "casa", "pos": Vector3(-315.0, -1.15, 46.0), "frente": Vector3(0, 0, -1), "garagem": Vector3(-322.0, -1.15, 42.0), "preco": 20000, "vagas": 3},
	{"id": "casa_2", "nome": "Casa 2", "tipo": "casa", "pos": Vector3(-382.0, -1.15, -289.0), "frente": Vector3(1, 0, 0), "garagem": Vector3(-389.0, -1.15, -285.0), "preco": 22500, "vagas": 3},
	{"id": "casa_3", "nome": "Casa 3", "tipo": "casa", "pos": Vector3(9.0, -1.15, -369.0), "frente": Vector3(0, 0, 1), "garagem": Vector3(9.0, -1.15, -361.0), "preco": 25000, "vagas": 3},
	{"id": "casa_4", "nome": "Casa 4", "tipo": "casa", "pos": Vector3(105.0, -1.15, -258.0), "frente": Vector3(0, 0, 1), "garagem": Vector3(105.0, -1.15, -250.0), "preco": 27500, "vagas": 3},
	{"id": "casa_5", "nome": "Casa 5", "tipo": "casa", "pos": Vector3(-182.0, -1.15, 139.0), "frente": Vector3(-1, 0, 0), "garagem": Vector3(-190.0, -1.15, 139.0), "preco": 30000, "vagas": 3},
	{"id": "casa_6", "nome": "Casa 6", "tipo": "casa", "pos": Vector3(-463.0, -1.15, -180.0), "frente": Vector3(0, 0, 1), "garagem": Vector3(-463.0, -1.15, -172.0), "preco": 32500, "vagas": 3},
	{"id": "casa_7", "nome": "Casa 7", "tipo": "casa", "pos": Vector3(120.0, -1.15, 59.0), "frente": Vector3(-1, 0, 0), "garagem": Vector3(112.0, -1.15, 59.0), "preco": 35000, "vagas": 3},
	{"id": "casa_8", "nome": "Casa 8", "tipo": "casa", "pos": Vector3(-282.0, -1.15, -491.0), "frente": Vector3(0, 0, -1), "garagem": Vector3(-282.0, -1.15, -499.0), "preco": 37500, "vagas": 3},
	{"id": "casa_9", "nome": "Casa 9", "tipo": "casa", "pos": Vector3(-435.0, -1.15, 116.0), "frente": Vector3(0, 0, -1), "garagem": Vector3(-435.0, -1.15, 108.0), "preco": 40000, "vagas": 3},
]


static func poi(id):
	for p in POIS:
		if p["id"] == id:
			return p
	return null


static func casas():
	var r = []
	for p in POIS:
		if p["tipo"] == "casa":
			r.append(p)
	return r
