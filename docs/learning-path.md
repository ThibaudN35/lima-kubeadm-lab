# Parcours d'apprentissage

L'objectif est d'expliquer chaque étape avant de l'automatiser. Pour chaque
manipulation, formuler une hypothèse, lancer une commande ciblée, observer le
résultat, puis conclure uniquement sur ce que ce résultat démontre.

Les commandes de création, démarrage et arrêt ci-dessous sont destinées aux
séances futures. Elles ne sont pas exécutées lors de la préparation du socle.
Aucun résultat de VM ou de cluster n'est encore acquis.

## 1. Lire et valider les définitions

Lire le README, le YAML du control plane et l'architecture. Repérer le moteur,
l'architecture CPU, les ressources, l'image et le réseau. Les noms d'instances
sont fournis par le Makefile, pas par les noms des fichiers YAML.

```sh
limactl --version
make
make validate
make status
```

Attendu : version de référence 2.1.1, aide, puis validation réussie des trois
YAML. `status` peut afficher une liste vide si rien n'a été créé. Une validation
réussie confirme l'acceptation statique des définitions, pas le fonctionnement
des invités. Une autre version de Lima demande de revalider les comportements.

## 2. Créer puis démarrer une première VM

Commencer avec le control plane pour limiter la consommation et isoler les
éventuels problèmes. La création et le démarrage sont deux actions distinctes.

```sh
make create NODE=cp
make status NODE=cp
make start NODE=cp
make status NODE=cp
limactl shell --workdir=/ lima-kubeadm-cp
```

Attendu : une instance créée puis démarrée, et un shell Linux accessible par SSH.
Si le démarrage échoue, conserver le message d'erreur, examiner l'état de cette
instance et rechercher sa cause avant de réessayer. Ne pas supprimer une VM
pour masquer un échec.

## 3. Vérifier le système réel

Les commandes suivantes se lancent **dans le shell Linux de la VM** et lisent
son état :

| Hypothèse | Commande | Résultat attendu et limite |
| --- | --- | --- |
| L'invité utilise ARM64 | `uname -m` | `aarch64`. Cela décrit l'architecture du noyau invité. |
| L'OS est Ubuntu 24.04 | `cat /etc/os-release` | Vérifier Ubuntu et `VERSION_ID="24.04"`. Le numéro de build/point release peut apporter une précision supplémentaire. |
| Deux CPU sont présentés | `lscpu` | Vérifier le nombre de CPU visibles ; ce n'est pas une mesure de performance. |
| La mémoire correspond au rôle | `free -h` | Environ 4 Gio pour le control plane, 2 Gio pour un worker ; la mémoire utilisable est inférieure à l'allocation nominale. |
| Le disque correspond au rôle | `lsblk` puis `df -h /` | Distinguer capacité du disque, partitions et espace utilisable du système de fichiers. |
| Le réseau est configuré | `ip -br address` puis `ip route` | Relever les vraies interfaces, adresses et routes sans les deviner. |
| DNS puis HTTPS fonctionnent | `getent ahostsv4 cloud-images.ubuntu.com` puis `curl --head --fail --show-error https://cloud-images.ubuntu.com/` | Le premier vérifie la résolution ; le second vérifie une requête HTTPS vers cette destination seulement. |

Ces outils sont à vérifier dans l'image. Si une commande n'est pas disponible,
noter ce manque ; ne pas lancer d'installation implicite dans cette étape.
HTTPS peut être influencé par un proxy hérité ; un résultat positif ne prouve
pas l'accès à tous les futurs registres et dépôts de paquets.

Sortir avec `exit`, puis arrêter la VM depuis le Mac si la séance s'arrête :

```sh
make stop NODE=cp
make status NODE=cp
```

L'arrêt libère les ressources de calcul de l'invité ; ses disques et sa
configuration restent présents. Le prochain démarrage utilisera cet état.

## 4. Ajouter les workers et tester les échanges

Après avoir validé la première VM et observé la mémoire du Mac, créer puis
démarrer chaque worker séparément :

```sh
make create NODE=worker-1
make start NODE=worker-1
make create NODE=worker-2
make start NODE=worker-2
make status
```

Le control plane doit aussi être démarré pour les tests entre nœuds. Refaire les
lectures système de l'étape 3 sur chaque worker, avec le nom correspondant :

```sh
limactl shell --workdir=/ lima-kubeadm-worker-1
```

Depuis un worker, essayer la résolution du control plane :

```sh
getent ahostsv4 lima-lima-kubeadm-cp.internal
```

Depuis le control plane, essayer celle des workers :

```sh
getent ahostsv4 lima-lima-kubeadm-worker-1.internal
getent ahostsv4 lima-lima-kubeadm-worker-2.internal
```

Comparer les résultats aux adresses effectivement relevées dans les invités.
Le double préfixe `lima-lima-` vient de la convention DNS Lima et du nom des VM.

Tester ensuite, depuis chaque VM, les deux autres destinations. Après avoir
vérifié l'existence de `ping` et de `nc`, la forme du test est :

```sh
ping -c 3 <PEER_IP>
nc -vz -w 3 <PEER_IP> 22
```

Remplacer `<PEER_IP>` par une adresse réellement observée ; ce marqueur n'est
pas une commande prête à copier. Un ping réussi prouve un échange ICMP, pas
l'accès à l'API. Une connexion TCP au port 22 prouve seulement que ce port est
joignable ; un timeout ne désigne pas à lui seul un pare-feu.

Si une étape échoue, progresser dans l'ordre : résolution DNS, adresse et route,
puis TCP, puis service. Retester DNS et HTTPS depuis chaque invité. Les flux
Kubernetes et ceux du futur CNI demanderont leurs propres vérifications ; ils
ne sont pas validés par ces tests SSH.

Une fois la séance terminée, `make stop` arrête les trois instances si elles
existent. Pour une machine seule, utiliser son sélecteur. Ne pas arrêter les
profils Colima avec les commandes de ce laboratoire.

## 5. Préparer Linux, lors d'une étape distincte

Avant toute installation, choisir une version Kubernetes supportée et consulter
sa documentation. Examiner les prérequis : identités distinctes des machines,
runtime compatible CRI, cgroups, politique de swap, routage et flux réseau,
résolution des noms et disponibilité des dépôts de paquets.

Cette phase modifiera les invités. Préparer alors un lot séparé avec les
commandes, les versions, les contrôles et le retour arrière adaptés. Ce socle
ne désactive pas le swap, ne règle aucun paramètre noyau et n'installe aucun
paquet Kubernetes ou containerd.

Référence officielle à relire pour la version choisie :
[installation de kubeadm](https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/install-kubeadm/).

## 6. Installer Kubernetes manuellement avec kubeadm

Comprendre successivement l'initialisation du control plane, le kubeconfig,
le choix et l'installation du CNI, puis le rattachement des workers. Les
versions des composants et les plages réseau devront être explicites.

Vérifier ensuite les nœuds, les Pods système et les échanges. Pratiquer d'abord
depuis le control plane ; préparer l'accès depuis le Mac après avoir observé
l'adresse et le certificat de l'API. Voir la section dédiée dans
[l'architecture](architecture.md).

Les kubeconfigs administrateur, clés et jetons de rattachement donnent des
droits sensibles. Les garder dans un emplacement local protégé ; ne pas les
copier dans la documentation, les commits, les sorties de diagnostic partagées
ou les exemples. Les commandes contenant un vrai jeton ne sont pas des notes
de cours à conserver dans Git.

## 7. Déployer une application de démonstration

Choisir une image de conteneur compatible ARM64 et un manifeste minimal.
Observer Deployment, Pods, Service, répartition entre workers et accès à
l'application. Tester le comportement lors de l'arrêt d'un worker seulement
après avoir prévu les conséquences pour l'application et ses données.

Conserver les manifestes non sensibles dans Git. Deux workers et plusieurs
réplicas ne rendent pas le control plane ou le Mac hautement disponibles.

## 8. Introduire Ansible après les manipulations

À partir des commandes comprises et vérifiées, définir le périmètre d'Ansible :
préparation Linux, runtime et installation des paquets. Construire ensuite un
inventaire utilisant l'accès SSH réellement observé. Éviter de figer des IP
supposées ou de dupliquer les clés Lima dans le dépôt.

L'idempotence se vérifiera sur une seconde exécution : les tâches conformes ne
doivent pas provoquer de changements inutiles. La création des VM restera la
responsabilité de Lima ; l'initialisation avec kubeadm restera manuelle jusqu'à
une décision explicite de l'automatiser. Aucun rôle ni playbook factice n'est
créé à ce stade.
