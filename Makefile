# Atajos para la demo. Todo corre con podman (MOTOR=docker también vale).
export MOTOR ?= podman
TAG ?= v1
KUBECTL = kubectl --kubeconfig kubeconfig

.PHONY: help cluster imagen borrar fmt test $(KUBE) $(AWS) \
        yaml-dev yaml-prod helm-dev helm-prod

help:  ## Muestra esta ayuda
	@grep -hE '^[a-z%][a-z% -]*:.*## ' $(MAKEFILE_LIST) | sed 's/:.*## /\t/'

cluster:  ## Crea el clúster k3s local (localhost:8080-8085)
	scripts/cluster.sh crear
imagen:  ## Construye la imagen y la carga en el clúster (TAG=v1)
	scripts/cluster.sh cargar $(TAG)
borrar:  ## Elimina el clúster
	scripts/cluster.sh borrar

# ---- OpenTofu: un solo proyecto en tofu/, la plataforma se elige con una variable ----
# Cada entorno es un workspace + tofu/entornos/<entorno>.tfvars (plataforma = "...").
KUBE = dev-kube prod-kube
AWS  = dev-lambda prod-lambda dev-beanstalk prod-beanstalk
# La imagen sólo se pasa en los entornos de Kubernetes.
img = $(if $(filter %-kube,$(1)),-var imagen=localhost/contador:$(TAG))

dev-kube prod-kube:  ## OpenTofu apply en el clúster local → dev-kube :8080, prod-kube :8081
	scripts/tofu.sh $@ init -input=false
	scripts/tofu.sh $@ apply $(call img,$@)
dev-lambda prod-lambda dev-beanstalk prod-beanstalk:  ## OpenTofu apply en AWS DE VERDAD (cuesta dinero; pide confirmación)
	scripts/tofu.sh $@ init -input=false
	scripts/tofu.sh $@ apply
plan-%:  ## OpenTofu plan de un entorno (plan-dev-kube, plan-prod-lambda…)
	scripts/tofu.sh $* init -input=false
	scripts/tofu.sh $* plan $(call img,$*)
destruir-%:  ## OpenTofu destroy de un entorno (destruir-dev-beanstalk…)
	scripts/tofu.sh $* init -input=false
	scripts/tofu.sh $* destroy
fmt:
	scripts/tofu.sh fmt -recursive
test:  ## tofu test: las tres plataformas, simulado (sin clúster ni cuenta de AWS)
	scripts/tofu.sh init -input=false -backend=false
	scripts/tofu.sh test

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
