# lima-kubeadm-lab

Un laboratoire Kubernetes reproductible utilisant des VM Lima et kubeadm sur Apple Silicon.

Ce dépôt commence par décrire les machines et leur cycle de vie. L'objectif est de
comprendre et pratiquer l'installation avec kubeadm manuellement, puis de rendre
la préparation des systèmes reproductible avec Ansible.

**État du projet : socle uniquement.** Les fichiers ne créent aucun cluster et
n'installent ni Kubernetes ni containerd. La validation statique ne prouve pas
qu'une VM démarre ou que son réseau fonctionne.

## Principes

- **Lima** décrit et gère les VM Linux ; son moteur `vz` utilise la virtualisation Apple.
- **Colima** fournit un environnement de conteneurs reposant sur Lima. Il est
  indépendant de ce laboratoire : aucune commande du dépôt ne gère ses profils.
- **Ansible** servira plus tard à configurer les systèmes Linux.
- **kubeadm** servira ensuite à initialiser le control plane et rattacher les workers.
- **Kubernetes** orchestrera les applications une fois ces étapes réalisées.

Le mode `plain` laisse la préparation des systèmes à l'utilisateur. Lima conserve
le mécanisme d'amorçage nécessaire à la VM et à SSH ; ce mode ne signifie pas une
absence complète de cloud-init. Aucun script de provisioning n'est fourni ici.

## Prérequis et ressources

Environnement cible déclaré : Mac mini M4, 16 Go de RAM, Lima **2.1.1** déjà
installé. Les commandes s'appuient sur GNU Make (compatible 3.81), le shell du Mac
et SSH ; aucune dépendance supplémentaire n'est demandée.

- Apple Silicon et macOS compatible avec le moteur `vz` (macOS 13 ou ultérieur).
- Accès HTTPS aux images Ubuntu lors de la future création.
- Espace disque pour les VM, les caches d'images et leurs données futures.
- Les profils Colima `dev` et `k3s` sont déclarés arrêtés dans le contexte du projet ;
  leur état n'est pas vérifié par les commandes de ce dépôt.

| Sélecteur `NODE` | Instance Lima | vCPU | Mémoire | Disque virtuel |
| --- | --- | ---: | ---: | ---: |
| `cp` | `lima-kubeadm-cp` | 2 | 4 Gio | 30 Gio |
| `worker-1` | `lima-kubeadm-worker-1` | 2 | 2 Gio | 25 Gio |
| `worker-2` | `lima-kubeadm-worker-2` | 2 | 2 Gio | 25 Gio |
| Total | Trois VM | 6 | **8 Gio** | **80 Gio** |

Les 8 Gio sont le budget des invités. Il faut y ajouter le coût de la
virtualisation, macOS, les applications et tout Colima actif. Les 80 Gio sont les
capacités virtuelles cumulées ; l'occupation réelle varie avec les écritures et
ne comprend pas les caches. Commencer avec le control plane seul permet
d'observer la pression mémoire avant d'ajouter les workers.

## Contenu du dépôt

```text
README.md
.gitignore
Makefile
machines/
  control-plane.yaml
  worker-1.yaml
  worker-2.yaml
docs/
  architecture.md
  learning-path.md
```

## Commandes

À lancer depuis la racine du dépôt. `NODE=all` est la valeur par défaut ; les
autres valeurs acceptées sont `cp`, `worker-1` et `worker-2`.

| Commande | Effet |
| --- | --- |
| `make` ou `make help` | Affiche l'aide, sans écriture. |
| `make validate` | Valide les trois YAML dans un environnement temporaire isolé. |
| `make validate NODE=cp` | Valide seulement le YAML du control plane. |
| `make status` | Affiche seulement les instances existantes de ce laboratoire. |
| `make create NODE=cp` | Crée l'instance, prépare l'image et les disques, sans démarrer la VM. |
| `make start NODE=cp` | Démarre une instance préalablement créée. |
| `make stop NODE=cp` | Arrête normalement une instance existante. |

`create`, `start` et `stop` modifient l'état local : exécute-les seulement au moment
de pratiquer. Aucune de ces opérations n'est une dépendance de `validate`.

`create` refuse le lot si un des noms sélectionnés existe déjà. `start` et `stop`
vérifient d'abord l'existence de tous les noms sélectionnés. Cela évite notamment
que `limactl start` crée implicitement une instance absente. Les commandes sont
séquentielles et s'arrêtent à la première erreur : une erreur en cours de lot
peut laisser les premières opérations déjà effectuées. Consulter `make status`
avant de décider de la suite ; aucune suppression ou annulation automatique
n'est prévue.

La validation utilise `limactl validate`, sans `--fill`, avec un `LIMA_HOME`
temporaire sous `/private/tmp`. Lima peut y produire sa configuration réseau ;
le répertoire est nettoyé à la sortie. Elle ne lit pas les personnalisations de
ton environnement Lima habituel, ne télécharge pas l'image et ne crée pas de VM.
Les commandes de gestion utilisent, elles, le `LIMA_HOME` actif, ou `~/.lima` par
défaut. Conserve le même environnement pour gérer tes instances.

## Première manipulation, à effectuer plus tard

Après la validation, commencer avec une seule VM :

```sh
make create NODE=cp
make status NODE=cp
make start NODE=cp
limactl shell --workdir=/ lima-kubeadm-cp
```

`create` enregistre la configuration de l'instance et prépare ses disques ; cette
commande peut déjà télécharger l'image si elle n'est pas en cache. `start`
lance ensuite la VM et son amorçage Linux. Les deux étapes produisent des états
locaux ; elles restent distinctes de l'installation future de Kubernetes.

`limactl shell` utilise SSH. `--workdir=/` évite de demander un répertoire du Mac
qui n'est pas partagé en mode `plain`. Pour sortir du shell invité : `exit`.
Puis, depuis le Mac :

```sh
make stop NODE=cp
make status NODE=cp
```

Le même parcours s'applique aux workers en remplaçant le sélecteur et le nom
d'instance. `make start` seul sélectionne les trois VM et exige qu'elles existent
toutes ; il ne crée pas les machines manquantes.

## Suite du parcours

Lire [l'architecture](docs/architecture.md) pour le réseau `user-v2`, l'accès
futur à l'API depuis le Mac et les limites de reproductibilité. Suivre ensuite
le [parcours d'apprentissage](docs/learning-path.md), qui distingue commande,
résultat attendu et observation réelle.

Les YAML sont des sources de création. Les configurations effectives conservées
par Lima sont des copies indépendantes : modifier `machines/*.yaml` ne met pas
automatiquement à jour une instance existante.

Les états locaux et fichiers sensibles doivent rester hors de Git. Les règles
de `.gitignore` couvrent les noms courants, mais ne détectent pas un secret placé
dans un fichier ordinaire et ne retirent pas un fichier déjà suivi.

## Références

Les commandes ont été confrontées à l'aide locale de Lima 2.1.1 et à ses sources
officielles. Les liens vers la documentation en ligne peuvent évoluer ; les
liens portant le tag `v2.1.1` constituent la référence de version.

- [Version Lima 2.1.1](https://github.com/lima-vm/lima/releases/tag/v2.1.1).
- [Configuration de référence, tag v2.1.1](https://github.com/lima-vm/lima/blob/v2.1.1/templates/default.yaml).
- [Commandes create/start, tag v2.1.1](https://github.com/lima-vm/lima/blob/v2.1.1/cmd/limactl/start.go).
- [Préparation des images et disques, tag v2.1.1](https://github.com/lima-vm/lima/blob/v2.1.1/pkg/instance/start.go).
- [Validation des modèles, tag v2.1.1](https://github.com/lima-vm/lima/blob/v2.1.1/cmd/limactl/template.go).
- [Accès SSH Lima](https://lima-vm.io/docs/usage/ssh/).
