# Atajos para la demo. Todo corre con podman (MOTOR=docker también vale).
export MOTOR ?= podman
TAG ?= v1
KUBECTL = kubectl --kubeconfig kubeconfig

.PHONY: help cluster imagen borrar init dev prod fmt aws-test lambda \
        yaml-dev yaml-prod helm-dev helm-prod

help:  ## Muestra esta ayuda
	@grep -hE '^[a-z%][a-z% -]*:.*## ' $(MAKEFILE_LIST) | sed 's/:.*## /\t/'

cluster:  ## Crea el clúster k3s local (localhost:8080-8085)
	scripts/cluster.sh crear
imagen:  ## Construye la imagen y la carga en el clúster (TAG=v1)
	scripts/cluster.sh cargar $(TAG)
borrar:  ## Elimina el clúster
	scripts/cluster.sh borrar

# ---- Vía 1: Terraform (terraform/) ----
init:
	scripts/tf.sh dev init -input=false
dev prod: init  ## Terraform apply del entorno → :8080 / :8081
	scripts/tf.sh $@ apply -var imagen=localhost/contador:$(TAG)
plan-%: init  ## Terraform plan (plan-dev, plan-prod)
	scripts/tf.sh $* plan -var imagen=localhost/contador:$(TAG)
destruir-%: init  ## Terraform destroy (destruir-dev, destruir-prod)
	scripts/tf.sh $* destroy
fmt:
	scripts/tf.sh dev fmt -recursive

# ---- Vía 2: manifiestos + kustomize (k8s/) ----
yaml-dev yaml-prod:  ## kubectl apply -k → :8082 / :8083
	$(KUBECTL) apply -k k8s/$(subst yaml-,,$@)
	$(KUBECTL) -n contador-$@ rollout status deploy/contador --timeout=3m
quitar-yaml-%:  ## kubectl delete -k
	$(KUBECTL) delete -k k8s/$*

# ---- Vía 3: Helm (helm/contador) ----
helm-dev helm-prod:  ## helm upgrade --install → :8084 / :8085
	scripts/helm.sh upgrade --install contador helm/contador --wait --timeout 3m \
	  -n contador-$@ --create-namespace -f helm/contador/values-$(subst helm-,,$@).yaml \
	  --set imagen.tag=$(TAG)
quitar-helm-%:  ## helm uninstall
	scripts/helm.sh uninstall contador -n contador-helm-$* --wait
	$(KUBECTL) delete namespace contador-helm-$*

# ---- Alternativa en AWS, todo simulado (terraform/aws) ----
aws-test:  ## Pruebas de la Lambda y terraform test con AWS simulado (sin cuenta)
	$(MOTOR) run --rm --security-opt label=disable -v "$(CURDIR)/lambda:/l:ro" -w /l \
	  docker.io/library/node:22-alpine node --test
	scripts/tf.sh aws init -input=false
	scripts/tf.sh aws test

lambda:  ## Instala las dependencias de la Lambda (sólo para desplegar de verdad)
	$(MOTOR) run --rm --security-opt label=disable -v "$(CURDIR)/lambda:/l" -w /l \
	  docker.io/library/node:22-alpine npm ci --omit=dev
