# Atajos para la demo. Todo corre con podman (MOTOR=docker también vale).
export MOTOR ?= podman
TAG ?= v1
KUBECTL = kubectl --kubeconfig kubeconfig

.PHONY: help cluster imagen borrar fmt aws-test $(KUBE) $(AWS) \
        yaml-dev yaml-prod helm-dev helm-prod

help:  ## Muestra esta ayuda
	@grep -hE '^[a-z%][a-z% -]*:.*## ' $(MAKEFILE_LIST) | sed 's/:.*## /\t/'

cluster:  ## Crea el clúster k3s local (localhost:8080-8085)
	scripts/cluster.sh crear
imagen:  ## Construye la imagen y la carga en el clúster (TAG=v1)
	scripts/cluster.sh cargar $(TAG)
borrar:  ## Elimina el clúster
	scripts/cluster.sh borrar

# ---- Entornos con Terraform: un workspace y un .tfvars por entorno ----
KUBE = dev-kube prod-kube
AWS  = dev-lambda prod-lambda dev-beanstalk prod-beanstalk
# La imagen sólo se pasa en los entornos de Kubernetes.
img = $(if $(filter %-kube,$(1)),-var imagen=localhost/contador:$(TAG))

dev-kube prod-kube:  ## Terraform apply en el clúster local → dev-kube :8080, prod-kube :8081
	scripts/tf.sh $@ init -input=false
	scripts/tf.sh $@ apply $(call img,$@)
dev-lambda prod-lambda dev-beanstalk prod-beanstalk:  ## Terraform apply en AWS DE VERDAD (cuesta dinero; pide confirmación)
	scripts/tf.sh $@ init -input=false
	scripts/tf.sh $@ apply
plan-%:  ## Terraform plan de un entorno (plan-dev-kube, plan-prod-lambda…)
	scripts/tf.sh $* init -input=false
	scripts/tf.sh $* plan $(call img,$*)
destruir-%:  ## Terraform destroy de un entorno (destruir-dev-beanstalk…)
	scripts/tf.sh $* init -input=false
	scripts/tf.sh $* destroy
fmt:
	scripts/tf.sh kube fmt -recursive
aws-test:  ## terraform test de los entornos de AWS, simulado (sin cuenta)
	scripts/tf.sh aws init -input=false
	scripts/tf.sh aws test

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
