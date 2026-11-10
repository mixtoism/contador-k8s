# Atajos para la demo. MOTOR=podman por defecto (MOTOR=docker también vale).
export MOTOR ?= podman
TAG ?= v1

.PHONY: cluster imagen init dev prod plan-dev plan-prod destruir-dev destruir-prod borrar fmt

cluster:             ## Crea el clúster k3s local
	scripts/cluster.sh crear
imagen:              ## Construye la imagen y la carga en el clúster
	scripts/cluster.sh cargar $(TAG)
init:
	scripts/tf.sh dev init
dev prod: init       ## Despliega un entorno
	scripts/tf.sh $@ apply -var imagen=localhost/contador:$(TAG)
plan-%: init
	scripts/tf.sh $* plan -var imagen=localhost/contador:$(TAG)
destruir-%: init
	scripts/tf.sh $* destroy
borrar:              ## Elimina el clúster
	scripts/cluster.sh borrar
fmt:
	scripts/tf.sh dev fmt
