#!/bin/bash
.ONESHELL:

kubespray:
	git clone -b release-2.19 --single-branch https://github.com/kubernetes-sigs/kubespray.git
	cp -nprf kubespray/* myfiles/* .

.PHONY: install
install:
	/usr/bin/env python3 -m venv venv
	. venv/bin/activate
	pip install -r requirements.txt
	ansible-playbook id_rsa_generating.yml
	terraform init
	terraform apply -auto-approve
	if [ ! -f ~/.vault_pass ]
	  then
		  echo testpass > ~/.vault_pass
	fi
	ansible-galaxy install -r requirements.yml
	ansible-playbook -i dynamic_inventory.py --vault-password-file ~/.vault_pass -b -u=root main.yml -vv
	ansible-playbook -i dynamic_inventory.py kubectl_localhost.yml -vv

.PHONY: golang
golang:
	ansible-playbook golang.yaml

operator-sdk:
	export PATH=/usr/local/go/bin:$(PATH)
	git clone -b master --single-branch https://github.com/operator-framework/operator-sdk
	cd operator-sdk
	make install
	operator-sdk olm install
	kubectl -n olm wait --for=jsonpath='{.status.phase}'=Installing csv/packageserver --timeout=10s
	kubectl -n olm delete csv packageserver
	kubectl -n olm delete deploy catalog-operator packageserver
	kubectl -n olm delete pod -l olm.catalogSource=operatorhubio-catalog
	kubectl -n olm delete svc operatorhubio-catalog

.PHONY: es
es:
	ansible-playbook esoperator_deploy.yaml
	while ! kubectl -n elastic-system get secret esoperator-es-elastic-user
	  do
	    echo "Waiting for secret..."
			sleep 1
		done
.PHONY: fb
fb:
	ansible-playbook set_es_secret.yaml -vv
	ansible-playbook fboperator_deploy.yaml -vv

.PHONY: kee
kee:
	kubectl apply -f kube_ev_exp.yaml
	kubectl -n elastic-system get secret esoperator-es-elastic-user -o=jsonpath='{.data.elastic}' | base64 --decode; echo

.PHONY: ela
ela:
	kubectl create ns alerting
	helm repo add elastalert2 https://jertel.github.io/elastalert2/
	helm -n alerting install elastalert2 elastalert2/elastalert2 --values elastalert_values.yaml

.PHONY: clean
clean:
		rm -rf kubespray/ operator-sdk/

all: kubespray install golang operator-sdk es fb kee clean
