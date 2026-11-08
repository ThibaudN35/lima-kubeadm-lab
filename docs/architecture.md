# Architecture du laboratoire

## Responsabilités et périmètre

Lima crée des VM Linux à partir des définitions de `machines/` et pilote leur
cycle de vie. Le moteur `vz` exploite la virtualisation Apple ; l'architecture
`aarch64` correspond à ARM64. Les images Ubuntu Server 24.04 utilisées ici sont
des images cloud officielles, sans environnement graphique.

Colima utilise lui aussi Lima pour fournir des environnements de conteneurs.
Ses profils `dev` et `k3s` restent indépendants : le Makefile ne contient aucune
commande Colima et ne sélectionne que les trois noms `lima-kubeadm-*` du projet.
Il n'utilise ni sélection globale pour démarrer/arrêter, ni changement de
configuration globale du Mac.

Ansible prendra ensuite en charge la configuration Linux. kubeadm servira à
amorcer le cluster ; Kubernetes orchestrera les applications. Ces couches ne
sont pas installées par ce socle. Il n'y a ni runtime de conteneurs configuré,
ni réseau de Pods, ni API Kubernetes en fonctionnement.

## Topologie et ressources

| Rôle prévu | Nom d'instance | vCPU | Mémoire | Disque |
| --- | --- | ---: | ---: | ---: |
| Control plane | `lima-kubeadm-cp` | 2 | 4 Gio | 30 Gio |
| Worker | `lima-kubeadm-worker-1` | 2 | 2 Gio | 25 Gio |
| Worker | `lima-kubeadm-worker-2` | 2 | 2 Gio | 25 Gio |

Les trois VM partagent le même Mac et le même réseau Lima nommé `user-v2`.
Le budget invité est de 8 Gio de RAM ; macOS, la virtualisation, les applications
et les éventuels environnements Colima actifs s'y ajoutent. Les six vCPU sont
des processeurs virtuels, pas six cœurs physiques réservés exclusivement.

Un seul control plane représente un point de défaillance. Deux workers
permettront d'observer la répartition et la reprise de certaines applications,
mais n'apporteront pas de haute disponibilité au control plane ni au Mac.
L'arrêt ou la panne du Mac affecte tout le laboratoire. Ce projet est destiné
à l'apprentissage, sans garantie de disponibilité ni de sauvegarde.

## Pourquoi le mode plain ?

Avec `plain: true`, Lima désactive notamment ses montages et l'installation
automatique de containerd ; la détection automatique des ports applicatifs
n'est pas disponible. Le mécanisme d'amorçage Linux et l'accès SSH restent
nécessaires. Des scripts de provisioning explicitement fournis pourraient
encore s'exécuter ; le dépôt n'en contient aucun.

Ce choix permet d'observer les prérequis Linux et d'installer le runtime et
kubeadm consciemment, dans une étape ultérieure. Il évite de confondre la
création d'une machine avec l'installation d'un cluster.

## Réseau user-v2 : support et vérifications

`user-v2` est un réseau en espace utilisateur supportant les échanges entre
VM. Lima 2.1.1 inclut sa définition et le moteur `vz` gère ce réseau. Les trois
YAML le référencent par `networks: [{lima: user-v2}]`, sans fixer d'IP ou modifier
le réseau du Mac. Ce mode remplace le réseau utilisateur par défaut.

La configuration réseau réellement utilisée dépend du `LIMA_HOME` actif.
Une définition locale différente ou un conflit de sous-réseaux peut influencer
le résultat. Les valeurs par défaut du logiciel ne constituent pas une
observation du réseau de ce Mac.

La documentation Lima décrit les noms `lima-<NAME>.internal` entre invités. Le
nom attendu pour le control plane est donc `lima-lima-kubeadm-cp.internal` :
le premier préfixe appartient à la convention Lima et le second au nom choisi
pour l'instance. Ces noms ne sont pas supposés résolus directement par macOS.

Le support du réseau ne prouve pas que les VM créées se joignent. Au futur
démarrage, relever les interfaces, adresses, routes et résolutions DNS, puis
vérifier les communications dans les deux sens. Les commandes et les résultats
attendus figurent dans le [parcours](learning-path.md). L'accès à Internet doit
être vérifié séparément, avec DNS puis HTTPS. Un ping seul ne valide pas TCP,
TLS ou les ports nécessaires au cluster.

Le réseau des machines et le futur réseau des Pods sont deux sujets distincts.
Le CNI et ses flux TCP/UDP restent à choisir et tester ; les plages des Pods et
des Services devront éviter les réseaux existants, y compris VPN et Colima.
Une validation statique des YAML ne vérifie aucun de ces flux.

Sources : [réseau user-v2](https://lima-vm.io/docs/config/network/user-v2/),
[définition réseau v2.1.1](https://github.com/lima-vm/lima/blob/v2.1.1/pkg/networks/networks.TEMPLATE.yaml)
et [implémentation réseau du moteur vz v2.1.1](https://github.com/lima-vm/lima/blob/v2.1.1/pkg/driver/vz/vm_darwin.go).

## API Kubernetes depuis le Mac : étape future

L'adresse d'une VM sur `user-v2` n'est pas une adresse directement routable
depuis le Mac par défaut. `plain` ne fournit pas ici de redirection automatique
de l'API. Aucune adresse d'API ou connectivité Kubernetes n'est donc présumée.

La première utilisation de `kubectl` pourra se faire depuis le control plane,
une fois Kubernetes installé. Pour accéder ensuite à l'API depuis le Mac, une
solution à étudier sera une redirection SSH explicite liée à `127.0.0.1`.

Exemple de forme uniquement, **non exécutable sans remplacer les paramètres** :

```sh
ssh -S none -F "${LIMA_HOME:-$HOME/.lima}/lima-kubeadm-cp/ssh.config" \
  -N -o ExitOnForwardFailure=yes \
  -L "127.0.0.1:<LOCAL_PORT>:<API_ADDRESS>:6443" \
  lima-lima-kubeadm-cp
```

- Utiliser la configuration et l'alias SSH générés pour l'instance, sans lire
  ni copier les clés privées. Le chemin ci-dessus correspond au nom choisi.
- Remplacer `<LOCAL_PORT>` par un port libre et non privilégié sur le Mac.
- Remplacer `<API_ADDRESS>` par une adresse vérifiée et accessible depuis le
  control plane. `6443` est le port habituel de l'API ; vérifier le port réel.
- Le client atteindra un port local, mais le certificat présenté restera celui
  de l'API. Prévoir le nom TLS/SAN et le champ `tls-server-name` appropriés dans
  un kubeconfig local ; conserver la vérification du certificat et de sa CA.
- `-S none` désactive le partage d'une connexion SSH existante pour ce tunnel.
  Garder le tunnel au premier plan ; `Ctrl-C` le ferme. Ce tunnel TCP ne rend
  pas tout le réseau Kubernetes accessible depuis le Mac.

Lima 2.1.1 propose aussi `limactl tunnel`, un proxy SOCKS expérimental. Ce socle
ne l'ouvre pas et ne change pas les proxys globaux de macOS. Son utilisation
avec un client Kubernetes demanderait une configuration et des tests dédiés.

Références : [SSH Lima](https://lima-vm.io/docs/usage/ssh/),
[manuel OpenSSH pour les options SSH](https://man.openbsd.org/ssh),
[tunnel SOCKS v2.1.1](https://github.com/lima-vm/lima/blob/v2.1.1/cmd/limactl/tunnel.go),
[ports Kubernetes](https://kubernetes.io/docs/reference/networking/ports-and-protocols/)
et [configuration des clients Kubernetes](https://kubernetes.io/docs/reference/config-api/kubeconfig.v1/).

## Reproductibilité : ce qui est figé et ce qui varie

| Élément | Choix actuel | Limite |
| --- | --- | --- |
| Lima | Version de référence 2.1.1 ; `minimumLimaVersion: "2.1.1"` | Le champ définit un minimum, pas une égalité ni une installation automatique. Une autre version doit être revalidée. |
| Définitions VM | Trois YAML explicites, sans modèle `template:` hérité | Ils doivent être conservés et versionnés pour retrouver les choix. |
| Image Linux | Ubuntu 24.04 ARM64, build `20261017`, URL datée et SHA-256 | L'empreinte fixe les octets attendus ; Ubuntu peut retirer un ancien build. Aucun repli silencieux sur `release/` n'est prévu. |
| Système en fonctionnement | Image de départ identique | Les écritures et mises à jour ultérieures font diverger les invités. |
| Paquets futurs | Aucune sélection Kubernetes/containerd pour l'instant | Versions, dépôts, CNI et images de conteneurs devront être choisis et documentés. |

L'alias Ubuntu `release/` évolue. Le modèle Lima `template:ubuntu-24.04` possède
également une stratégie d'images pouvant inclure un repli évolutif ; il n'est
pas utilisé ici. La disponibilité de l'URL et la publication du SHA-256 ont été
vérifiées le 8 novembre 2026 ; le fichier image n'a pas été téléchargé ni sa
signature GPG vérifiée pendant la préparation du socle. Lima vérifiera son
empreinte lors du téléchargement futur.

Sources : [build Ubuntu](https://cloud-images.ubuntu.com/releases/noble/release-20261017/),
[SHA256SUMS Ubuntu](https://cloud-images.ubuntu.com/releases/noble/release-20261017/SHA256SUMS)
et [modèle d'images Ubuntu de Lima v2.1.1](https://github.com/lima-vm/lima/blob/v2.1.1/templates/_images/ubuntu-24.04.yaml).

## Sources du dépôt et état effectif de Lima

`make create` transmet le YAML source et un nom explicite à Lima. Cette commande
prépare aussi l'image et les disques et peut donc nécessiter un téléchargement,
même sans démarrer la VM. Lima conserve sa configuration effective sous
`${LIMA_HOME:-$HOME/.lima}/<INSTANCE>/lima.yaml`, avec ses autres états locaux.
Les réglages globaux locaux `default.yaml`, `override.yaml` ou `base.yaml`
peuvent également influencer une création. Ils ne sont ni modifiés ni affichés
par ce dépôt.

Un changement de `machines/control-plane.yaml` ne modifie donc pas une instance
déjà créée. `make start` relit l'instance existante ; il n'applique pas le YAML
source. Le nommage dans le Makefile identifie les instances, sans prouver leur
conformité au dernier YAML du dépôt.

Avant une future reconfiguration, comparer les choix sources et l'état effectif,
puis préparer une opération distincte. Une recréation peut supprimer les données
de l'invité : elle exige une décision explicite et, si nécessaire, une sauvegarde.
Il n'existe aucune cible de suppression ou de réinitialisation dans ce dépôt.

## Validation sans configuration globale

Dans Lima 2.1.1, charger la configuration d'un réseau nommé peut produire
`_config/networks.yaml` s'il manque. Le Makefile donne à la validation un
`LIMA_HOME` temporaire sous `/private/tmp`, puis nettoie ce répertoire uniquement.
Les YAML n'héritent d'aucun modèle externe : la validation n'a pas à télécharger
une image ou un modèle. Elle contrôle les fichiers avec les valeurs par défaut
du logiciel, indépendamment des personnalisations globales de l'utilisateur.

Cette isolation protège l'environnement habituel, mais ne valide pas ses
éventuelles personnalisations, le démarrage, les ressources disponibles ou le
réseau effectif. Les phases futures de création et de démarrage créeront leurs
propres états dans le `LIMA_HOME` actif, et pourront initialiser sa configuration
réseau si elle manque.

Sources de version : [chargement réseau v2.1.1](https://github.com/lima-vm/lima/blob/v2.1.1/pkg/networks/config.go),
[validation des modèles v2.1.1](https://github.com/lima-vm/lima/blob/v2.1.1/cmd/limactl/template.go)
et [chargement YAML v2.1.1](https://github.com/lima-vm/lima/blob/v2.1.1/pkg/limayaml/load.go).
