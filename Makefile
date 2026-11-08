SHELL := /bin/sh
.DEFAULT_GOAL := help

NODE ?= all
NODES := cp worker-1 worker-2

ifneq ($(words $(NODE)),1)
$(error NODE doit valoir all, cp, worker-1 ou worker-2)
endif
ifneq ($(filter all $(NODES),$(NODE)),$(NODE))
$(error NODE inconnu : utiliser all, cp, worker-1 ou worker-2)
endif

ifeq ($(NODE),all)
SELECTED_NODES := $(NODES)
INSTANCE_FILTER := .name == "lima-kubeadm-cp" or .name == "lima-kubeadm-worker-1" or .name == "lima-kubeadm-worker-2"
else
SELECTED_NODES := $(NODE)
INSTANCE_FILTER := .name == "lima-kubeadm-$(NODE)"
endif

MACHINE_cp := machines/control-plane.yaml
MACHINE_worker-1 := machines/worker-1.yaml
MACHINE_worker-2 := machines/worker-2.yaml
INSTANCES := $(addprefix lima-kubeadm-,$(SELECTED_NODES))
MACHINES := $(foreach node,$(SELECTED_NODES),$(MACHINE_$(node)))

.PHONY: help validate status create start stop

help:
	@printf '%s\n' \
	  'Laboratoire Lima / kubeadm — version de référence : Lima 2.1.1' \
	  '' \
	  'make help      Afficher cette aide (cible par défaut)' \
	  'make validate  Valider les YAML ; aucune VM créée ou démarrée' \
	  'make status    Afficher seulement les instances du laboratoire' \
	  'make create    Créer les instances depuis les YAML, sans démarrer' \
	  'make start     Démarrer seulement des instances déjà créées' \
	  'make stop      Arrêter normalement les instances existantes' \
	  '' \
	  'Sélection : NODE=all (défaut), cp, worker-1 ou worker-2' \
	  'Exemple : make validate NODE=cp' \
	  'create, start et stop modifient des états locaux ; aucun effacement prévu.'

# Le réseau nommé peut provoquer une écriture par Lima pendant la validation.
# Isoler cette écriture ; ne pas charger les personnalisations globales du Mac.
validate:
	@set -eu; \
	validation_home=$$(mktemp -d /private/tmp/lima-kubeadm-validate.XXXXXX); \
	trap 'rm -rf -- "$$validation_home"' 0; \
	trap 'exit 130' INT; \
	trap 'exit 143' TERM; \
	LIMA_HOME="$$validation_home" limactl validate $(MACHINES)

# Un filtre exact retourne une liste vide si aucune instance du lab n'existe.
status:
	limactl list --filter '$(INSTANCE_FILTER)'

# Vérifier tous les noms avant la première création ; conserver les erreurs Lima.
create:
	@set -eu; \
	existing=$$(limactl list --quiet --filter '$(INSTANCE_FILTER)'); \
	if [ -n "$$existing" ]; then \
	  printf 'Création refusée : instances déjà existantes :\n%s\n' "$$existing" >&2; \
	  exit 1; \
	fi; \
	$(foreach node,$(SELECTED_NODES),limactl create --tty=false --name=lima-kubeadm-$(node) $(MACHINE_$(node));)

# Avec des noms explicites, list échoue si une seule instance manque.
# Ne jamais appeler start avec un nom absent ou avec un chemin YAML.
start:
	@set -eu; \
	limactl list --quiet $(INSTANCES) >/dev/null; \
	for instance in $(INSTANCES); do \
	  limactl start --tty=false "$$instance"; \
	done

stop:
	@set -eu; \
	limactl list --quiet $(INSTANCES) >/dev/null; \
	for instance in $(INSTANCES); do \
	  limactl stop "$$instance"; \
	done
