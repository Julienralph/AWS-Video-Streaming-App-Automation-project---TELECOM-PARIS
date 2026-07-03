# GIN208 - Documentation complète du projet
## AWS Video Streaming App Automation - Télécom Paris

**Auteur :** Julien Ralph (binôme : Steve)
**Cours :** GIN208 - Télécom Paris, promo 2025-2026
**Repo GitHub :** `Julienralph/AWS-Video-Streaming-App-Automation-project---TELECOM-PARIS`
**URL de production :** `https://projet-streaming-ralph-steve.devops.intuitivelabs.net`
**Compte AWS :** 708113109960, région us-east-1

---

## Table des matières

1. [Objectif du projet](#objectif)
2. [Architecture globale](#architecture)
3. [Environnement de travail](#environnement)
4. [Phase 1 : Infrastructure Terraform](#terraform)
5. [Phase 2 : Configuration Ansible](#ansible)
6. [Problèmes rencontrés et solutions](#problemes)
7. [Flux de données complet](#flux)
8. [Commandes de référence](#commandes)
9. [État actuel de l'infrastructure](#etat)

---

## 1. Objectif du projet <a name="objectif"></a>

Automatiser le déploiement complet d'une application de streaming vidéo en direct sur AWS, en utilisant :
- **Terraform** pour provisionner l'infrastructure (IaC - Infrastructure as Code)
- **Ansible** pour configurer les serveurs applicatifs

Le flux vidéo simulé : FFmpeg génère une mire de couleurs synthétique → encodée en temps réel → diffusée en HLS → accessible depuis un navigateur via CloudFront.

Ce projet simule l'infrastructure de streaming pour un système de téléopération (robotaxi) où une caméra embarquée envoie un flux vidéo vers un opérateur distant.

---

## 2. Architecture globale <a name="architecture"></a>

### 2.1 Vue d'ensemble

```
[Navigateur] → HTTPS → [Route53] → [CloudFront]
                                        ├── /         → [S3] (player HTML)
                                        └── /hls/*    → [ALB] → [Frontend EC2 NGINX]
                                                                      ↑ RTMP:1935
                                                              [Streamer EC2 FFmpeg]
```

### 2.2 Composants détaillés

| Composant | Service AWS | Rôle |
|---|---|---|
| DNS | Route53 | ALIAS vers CloudFront |
| CDN | CloudFront | 2 origines : S3 (player) + ALB (HLS) |
| TLS/SSL | ACM | Cert pour le domaine custom |
| Load Balancer | ALB | Terminaison HTTP, forward vers ASG |
| Auto Scaling | ASG + Launch Template | desired=1, min=1, max=3 |
| Frontend | EC2 t3.small Ubuntu 20.04 | NGINX + module RTMP |
| Stockage partagé | EFS | Segments HLS partagés entre instances ASG |
| Streamer | EC2 t3.small Ubuntu 20.04 | FFmpeg (génère le flux vidéo) |
| Player | S3 | HTML avec lecteur HLS.js |
| Monitoring | CloudWatch | Métriques CPU, mémoire, disque, logs |
| Alertes | SNS | Email sur alarme CPU > 70% |
| Budget | AWS Budget | Alerte à 20$ |
| Sécurité | GuardDuty + CloudTrail | Détection menaces + audit API |
| State Terraform | S3 + DynamoDB | Remote state versionné et verrouillé |

### 2.3 Réseau

```
VPC : 10.0.0.0/16 (us-east-1)
├── public_az_a  : 10.0.1.0/24  (Frontend A + Streamer + NAT GW + EFS MT)
├── public_az_b  : 10.0.2.0/24  (Frontend B + EFS MT)
├── private_az_a : 10.0.3.0/24  (réservé - plus de route Internet)
└── private_az_b : 10.0.4.0/24  (réservé - scaling futur)
```

**Important :** Le Streamer est dans `public_az_a`, pas dans un subnet privé. Le subnet privé prévu initialement pour le Streamer a été supprimé (plus de NAT Gateway dédié). Le Streamer sort directement via l'IGW.

### 2.4 Security Groups

**sg_alb (ALB) :**
- Ingress : TCP 443 depuis 0.0.0.0/0 (HTTPS utilisateurs)
- Ingress : TCP 80 depuis 0.0.0.0/0 (HTTP depuis CloudFront)
- Egress : TCP 80 vers sg_frontend

**sg_frontend (instances Frontend NGINX) :**
- Ingress : TCP 80 depuis sg_alb (trafic ALB uniquement)
- Ingress : TCP 1935 depuis sg_streamer (flux RTMP)
- Egress : TCP 2049 vers sg_efs (montage NFS EFS)
- Egress : TCP 443 vers 0.0.0.0/0 (mises à jour apt, AWS APIs)
- Egress : TCP 80 vers 0.0.0.0/0

**sg_streamer (instance Streamer FFmpeg) :**
- Ingress : aucune règle (pas d'accès entrant)
- Egress : TCP 1935 vers sg_frontend (push RTMP)
- Egress : TCP 443 vers 0.0.0.0/0 (mises à jour, téléchargements)
- Egress : TCP 80 vers 0.0.0.0/0

**sg_efs (EFS Mount Targets) :**
- Ingress : TCP 2049 depuis sg_frontend
- Egress : TCP 2049 vers sg_frontend

### 2.5 NACL (Network Access Control Lists)

Les NACLs sont stateless (contrairement aux SGs) : il faut explicitement autoriser aller ET retour.

**NACL Public (subnets public_az_a et public_az_b) :**
| # | Direction | Protocole | Ports | Source/Dest | Action |
|---|---|---|---|---|---|
| 90 | Ingress | TCP | 22 | 0.0.0.0/0 | Allow (SSH temporaire Ansible) |
| 100 | Ingress | TCP | 443 | 0.0.0.0/0 | Allow (HTTPS) |
| 110 | Ingress | TCP | 80 | 0.0.0.0/0 | Allow (HTTP) |
| 120 | Ingress | TCP | 1935 | 10.0.1.0/24 | Allow (RTMP intra-subnet) |
| 130 | Ingress | TCP | 1024-65535 | 0.0.0.0/0 | Allow (ports éphémères retour) |
| 100 | Egress | TCP | 443 | 0.0.0.0/0 | Allow |
| 110 | Egress | TCP | 80 | 0.0.0.0/0 | Allow |
| 120 | Egress | TCP | 1024-65535 | 0.0.0.0/0 | Allow (retour connexions entrantes) |

**NACL Privé (subnets private_az_a et private_az_b) :**
| # | Direction | Protocole | Ports | Source/Dest | Action |
|---|---|---|---|---|---|
| 100 | Ingress | TCP | 1024-65535 | 0.0.0.0/0 | Allow (retour Internet via NAT) |
| 110 | Ingress | TCP | 1024-65535 | 10.0.1.0/24 | Allow (retour RTMP) |
| 100 | Egress | TCP | 443 | 0.0.0.0/0 | Allow |
| 110 | Egress | TCP | 80 | 0.0.0.0/0 | Allow |
| 120 | Egress | TCP | 1935 | 10.0.1.0/24 | Allow (RTMP vers Frontend) |

---

## 3. Environnement de travail <a name="environnement"></a>

### 3.1 Setup WSL

Le projet tourne dans **WSL Ubuntu** sur Windows. Tout le code est dans `~/gin208/`.

```
~/gin208/
├── terraform/          # Infrastructure as Code
│   ├── providers.tf
│   ├── backend.tf
│   ├── variables.tf
│   ├── terraform.tfvars
│   ├── outputs.tf
│   ├── vpc.tf
│   ├── sg.tf
│   ├── nacl.tf
│   ├── alb.tf
│   ├── asg.tf
│   ├── efs.tf
│   ├── cloudfront.tf
│   ├── acm.tf
│   ├── route53.tf
│   ├── cloudwatch.tf
│   ├── s3.tf
│   └── templates/
│       └── user_data_frontend.sh.tpl
└── ansible/
    ├── ansible.cfg
    ├── inventory/
    │   └── aws_ec2.yaml       # Inventaire dynamique AWS
    ├── playbooks/
    │   ├── frontend.yml
    │   ├── streamer.yml
    │   └── cloudwatch-agent.yml
    ├── templates/
    │   └── nginx-rtmp.conf.j2
    └── vars/
        └── generic.yaml
```

### 3.2 Outils installés dans WSL

```bash
terraform --version    # v1.15.6
ansible --version      # Ansible 2.20.1 (ansible-core 2.17)
aws --version          # AWS CLI v2
python3 --version      # Python 3.10+ (sur la machine locale)
```

### 3.3 Credentials AWS

Le compte AWS est celui de Télécom Paris (SSO). Les credentials sont **temporaires** et expirent toutes les ~1h.

**Procédure de renouvellement :**
1. Aller dans AWS CloudShell (console AWS)
2. Exécuter :
   ```bash
   aws configure export-credentials --format env
   ```
3. Copier les 3 lignes `export` dans le terminal WSL :
   ```bash
   export AWS_ACCESS_KEY_ID=ASIA...
   export AWS_SECRET_ACCESS_KEY=...
   export AWS_SESSION_TOKEN=...
   ```

---

## 4. Phase 1 : Infrastructure Terraform <a name="terraform"></a>

### 4.1 Bootstrap (avant Terraform)

Avant d'utiliser Terraform avec un backend distant, il faut créer le bucket S3 et la table DynamoDB manuellement.

```bash
# Script bootstrap.sh exécuté une seule fois
# Crée : gin208-tfstate-ralph (S3) + gin208-locks-ralph (DynamoDB)
bash bootstrap.sh
```

**Pourquoi le suffixe `-ralph` ?** Le compte AWS est partagé entre tous les étudiants du cours. Pour éviter les conflits de noms, chaque étudiant ajoute son nom.

### 4.2 Backend Terraform (backend.tf)

```hcl
terraform {
  backend "s3" {
    bucket         = "gin208-tfstate-ralph"
    key            = "gin208/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "gin208-locks-ralph"
    encrypt        = true
  }
}
```

**Avantages du backend distant :**
- État versionné dans S3 (possibilité de rollback)
- Verrouillage via DynamoDB (évite les modifications simultanées)
- Partageable avec un binôme

### 4.3 Variables principales (terraform.tfvars)

```hcl
aws_region             = "us-east-1"
domain_name            = "projet-streaming-ralph-steve.devops.intuitivelabs.net"
route53_zone_name      = "devops.intuitivelabs.net"
alert_email            = "julien.sangongdjomo@telecom-paris.fr"
instance_type_frontend = "t3.small"
instance_type_streamer = "t3.small"
asg_desired            = 1
asg_min                = 1
asg_max                = 3
ami_id                 = "ami-0261755bbcb8c4a84"  # Ubuntu 20.04 LTS us-east-1
```

**Pourquoi t3.small (pas t2) ?** Génération Nitro, meilleur rapport prix/performance.

### 4.4 Workflow Terraform

```bash
cd ~/gin208/terraform

terraform init      # Initialise le backend et télécharge les providers
terraform plan      # Prévisualise les changements (sans les appliquer)
terraform apply     # Applique les changements
terraform destroy   # Détruit toute l'infrastructure (à n'utiliser qu'à la fin)
```

### 4.5 CloudFront - Configuration importante

CloudFront a **2 origines** :
- `s3-player` : sert `index.html` (le player HTML)
- `alb-frontend` : sert `/hls/*` (les segments vidéo)

**Routing par chemin :**
- `/*` → S3 (comportement par défaut, cache 24h)
- `/hls/*` → ALB (cache désactivé, contenu temps réel)

**Point critique :** L'origine ALB utilise `origin_protocol_policy = "http-only"`. CloudFront contacte l'ALB en HTTP (port 80). Le listener port 80 de l'ALB est configuré en `forward` (pas redirect) pour éviter une boucle 301.

### 4.6 ACM (Certificat TLS)

Le certificat couvre `projet-streaming-ralph-steve.devops.intuitivelabs.net`. La validation est automatique via Route53 (CNAME de validation créé par Terraform).

**Important :** Le cert ACM pour CloudFront DOIT être dans la région `us-east-1` (exigence AWS pour CloudFront). Un cert dans une autre région ne fonctionnerait pas.

---

## 5. Phase 2 : Configuration Ansible <a name="ansible"></a>

### 5.1 ansible.cfg

```ini
[defaults]
inventory = inventory/aws_ec2.yaml
remote_user = ubuntu
private_key_file = ~/.ssh/gin208-key
host_key_checking = False
collections_path = ~/.ansible/collections
forks = 5
interpreter_python = /usr/bin/python3.9
stdout_callback = default
result_format = yaml

[ssh_connection]
pipelining = True
ssh_args = -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null
```

**Points importants :**
- `interpreter_python = /usr/bin/python3.9` : Ansible 2.20 requiert Python 3.9+ sur les hôtes distants
- `stdout_callback = default` + `result_format = yaml` : le callback `community.general.yaml` a été supprimé dans Ansible 2.20, remplacé par cette combinaison
- `pipelining = True` : accélère les connexions SSH en réutilisant les sessions

### 5.2 Inventaire dynamique (aws_ec2.yaml)

L'inventaire dynamique découvre automatiquement les instances EC2 par leurs **tags AWS**. Plus besoin de maintenir un fichier d'IPs à la main.

```yaml
plugin: amazon.aws.aws_ec2
regions: [us-east-1]
filters:
  tag:Owner: julien-ralph
  instance-state-name: running
keyed_groups:
  - key: tags.Role
    prefix: role
```

Résultat : les instances taguées `Role: frontend` apparaissent dans le groupe `role_frontend`, celles taguées `Role: streamer` dans `role_streamer`.

**Commande de vérification :**
```bash
ansible role_frontend --list-hosts
ansible role_streamer --list-hosts
```

### 5.3 frontend.yml - Ce qu'il fait

1. Met à jour le cache apt
2. Installe NGINX + libnginx-mod-rtmp
3. Installe nfs-common (pour monter l'EFS en NFS4)
4. Crée le dossier `/mnt/efs/hls`
5. Monte l'EFS via NFS4
6. Déploie la config NGINX depuis le template Jinja2
7. Démarre et active NGINX au boot

**Commande d'exécution :**
```bash
cd ~/gin208/ansible
ansible-playbook playbooks/frontend.yml
```

### 5.4 streamer.yml - Ce qu'il fait

1. Met à jour le cache apt
2. Installe FFmpeg
3. Crée un service systemd `gin208-streamer`
4. Démarre le service FFmpeg au boot

Le service FFmpeg génère une mire de couleurs synthétique et la pousse en RTMP vers l'IP privée du Frontend :
```
/usr/bin/ffmpeg -re -f lavfi -i testsrc=size=1280x720:rate=25 \
  -f lavfi -i sine=frequency=440 \
  -c:v libx264 -preset veryfast -tune zerolatency \
  -b:v 1000k -maxrate 1000k -bufsize 2000k \
  -g 50 -keyint_min 25 \
  -c:a aac -b:a 128k \
  -f flv rtmp://10.0.2.241:1935/live/stream
```

**L'IP du Frontend est calculée dynamiquement** depuis l'inventaire :
```yaml
frontend_private_ip: "{{ hostvars[groups['role_frontend'][0]]['private_ip_address'] }}"
```

**Important :** Si le Frontend change d'IP (recyclage ASG), il faut relancer `streamer.yml` pour mettre à jour le service avec la nouvelle IP.

### 5.5 cloudwatch-agent.yml - Ce qu'il fait

1. Vérifie si l'agent CloudWatch est déjà installé
2. Si absent : télécharge et installe le `.deb` depuis S3 Amazon
3. Déploie la config JSON (métriques + logs)
4. Démarre l'agent

**Métriques collectées :**
- `mem_used_percent` (mémoire RAM, non disponible sans agent)
- `disk used_percent` (espace disque `/` et `/mnt/efs/hls`)
- `bytes_sent` / `bytes_recv` (réseau)

**Logs collectés :**
- `/var/log/nginx/access.log`
- `/var/log/nginx/error.log`

### 5.6 Template NGINX (nginx-rtmp.conf.j2)

Le template configure deux blocs :

**Bloc HTTP (port 80) :**
- `location /` : répond 200 OK (health check ALB)
- `location /hls` : sert les segments HLS depuis l'EFS (`root /mnt/efs`)

**Bloc RTMP (port 1935) :**
- Reçoit le flux de FFmpeg
- Découpe en segments HLS de 2 secondes
- Écrit les segments dans `/mnt/efs/hls/` (sur l'EFS partagé)

```nginx
include /etc/nginx/modules-enabled/*.conf;  # charge ngx_rtmp_module.so
worker_processes auto;
...
http {
    server {
        listen 80;
        server_name projet-streaming-ralph-steve.devops.intuitivelabs.net;
        location / { return 200 'OK'; }
        location /hls { root /mnt/efs; }
    }
}
rtmp {
    server {
        listen 1935;
        application live {
            live on;
            hls on;
            hls_path /mnt/efs/hls;
            hls_fragment 2s;
            hls_playlist_length 10s;
        }
    }
}
```

---

## 6. Problèmes rencontrés et solutions <a name="problemes"></a>

### Problème 1 : Python sur les instances EC2

**Symptôme :**
```
The module interpreter '/usr/bin/python3.10' was not found.
```

**Cause :** Ansible 2.20 (ansible-core 2.17) requiert Python 3.9+ sur les hôtes distants. Ubuntu 20.04 livré avec Python 3.8.10 par défaut. On avait configuré `interpreter_python = /usr/bin/python3.10` mais Python 3.10 n'existe pas sur Ubuntu 20.04.

**Tentative échouée : `apt-get install python3.10`**
Cette commande installe 558 paquets GNOME/QGIS (!) car apt traite le nom comme une regex et matche `libqgispython3.10.4` (QGIS version 3.10.4, pas Python 3.10). Le binaire `/usr/bin/python3.10` n'est jamais créé.

**Tentative échouée : deadsnakes PPA**
```bash
add-apt-repository ppa:deadsnakes/ppa
apt-get install python3.10-minimal
```
Deadsnakes ne supporte plus Ubuntu 20.04 (focal). Paquet introuvable.

**Solution finale : Python 3.9**
Python 3.9 est disponible nativement dans `focal-updates/universe` :
```bash
ansible role_frontend:role_streamer -m raw -a "apt-get install -y python3.9" --become
```
Résultat : 4 paquets seulement, `/usr/bin/python3.9` créé, version 3.9.5.

```bash
# Modification dans ansible.cfg :
interpreter_python = /usr/bin/python3.9
```

**Vérification :**
```bash
ansible role_frontend:role_streamer -m ping
# Résultat : SUCCESS pong sur les deux instances
```

---

### Problème 2 : Incompatibilité python3-apt / Python 3.9

**Symptôme :**
```
Could not import the python3-apt module using /usr/bin/python3.9
```

**Cause :** Le module `ansible.builtin.apt` utilise la librairie Python `python3-apt` pour interagir avec APT. Sur Ubuntu 20.04, `python3-apt` est compilé uniquement pour Python 3.8. Il n'existe pas de version pour Python 3.9 dans les dépôts officiels.

**Tentative échouée : `force_apt_get: true`**
```yaml
module_defaults:
  ansible.builtin.apt:
    force_apt_get: true
```
Censé contourner python3-apt en utilisant apt-get directement. En pratique, dans ansible-core 2.17, le module importe quand même python3-apt au démarrage avant de vérifier le flag.

**Tentative échouée : `auto_install_module_deps: false`**
Réduit le nombre de tentatives (3 → 2 JSONs dans stdout) mais ne résout pas le fond du problème. L'erreur de désérialisation JSON persiste car plusieurs blocs JSON apparaissent dans stdout.

**Solution finale : remplacer `ansible.builtin.apt` par `ansible.builtin.command`**
```yaml
# Avant (échoue) :
- name: Mise a jour du cache apt
  ansible.builtin.apt:
    update_cache: true

# Après (fonctionne) :
- name: Mise a jour du cache apt
  ansible.builtin.command: apt-get update -qq
  changed_when: false

- name: Installation de FFmpeg
  ansible.builtin.command: apt-get install -y ffmpeg
  args:
    creates: /usr/bin/ffmpeg  # Idempotence : skip si déjà installé
```

---

### Problème 3 : ASG qui recycle les instances en boucle

**Symptôme :** Les instances EC2 sont créées, puis terminées quelques minutes plus tard, remplacées par de nouvelles instances.

**Cause :** L'ALB fait des health checks toutes les 30s sur le port 80. Avant que NGINX soit installé et configuré, les instances ne répondent pas → health check échoue → ASG `ReplaceUnhealthy` termine l'instance et en crée une nouvelle → boucle infinie.

**Solution :** Suspendre les processus ASG pendant la configuration :
```bash
aws autoscaling suspend-processes \
  --auto-scaling-group-name gin208-asg-frontend \
  --scaling-processes HealthCheck ReplaceUnhealthy
```

Après configuration de NGINX et vérification que l'ALB voit l'instance comme healthy :
```bash
aws autoscaling resume-processes \
  --auto-scaling-group-name gin208-asg-frontend \
  --scaling-processes HealthCheck ReplaceUnhealthy
```

---

### Problème 4 : stdout_callback yaml supprimé

**Symptôme :**
```
community.general.yaml callback plugin has been removed
```

**Cause :** Le plugin `community.general.yaml` pour la sortie Ansible a été retiré dans Ansible 2.20.

**Solution dans ansible.cfg :**
```ini
# Avant :
stdout_callback = yaml

# Après :
stdout_callback = default
result_format = yaml
```

---

### Problème 5 : `{{ variable }}` dans un commentaire NGINX

**Symptôme :**
```
'variable' is undefined
Origin: nginx-rtmp.conf.j2
```

**Cause :** Le fichier `nginx-rtmp.conf.j2` contenait dans son en-tête de commentaire :
```
# Jinja2 = moteur de templates d'Ansible. Les {{ variable }} sont
```
Jinja2 traite TOUS les `{{ }}`, même ceux dans les commentaires NGINX (qui commencent par `#`). Le `#` est un commentaire NGINX, pas un commentaire Jinja2 (`{# ... #}`). Ansible cherche une variable nommée `variable` qui n'existe pas.

**Solution :** Supprimer les accolades du commentaire.

---

### Problème 6 : Module RTMP NGINX non chargé

**Symptôme :**
```
Unable to reload service nginx: Job for nginx.service failed.
```

**Cause :** Notre template `nginx-rtmp.conf.j2` remplace tout le fichier `nginx.conf`. Le bloc `rtmp {}` requiert le module dynamique `ngx_rtmp_module.so`. Sur Ubuntu, ce module est chargé via `/etc/nginx/modules-enabled/*.conf`. Comme notre template remplace nginx.conf sans inclure cette directive, NGINX ne sait pas ce qu'est le bloc `rtmp`.

**Solution :** Ajouter en tête du template :
```nginx
include /etc/nginx/modules-enabled/*.conf;
```

---

### Problème 7 : `amazon-efs-utils` introuvable

**Symptôme :**
```
E: Unable to locate package amazon-efs-utils
```

**Cause :** Sur ces instances Ubuntu 20.04, le dépôt `universe` n'est pas activé (le user_data a planté avec `cloud-init status: error`). `amazon-efs-utils` n'est pas dans les dépôts standard.

**Conséquence :** Sans `amazon-efs-utils`, le montage EFS avec `fstype: efs` échoue :
```
unknown filesystem type 'efs'
```

**Solution :** Utiliser le montage NFS4 natif (intégré au kernel Linux, aucun paquet supplémentaire nécessaire) :
```yaml
- name: Installation de nfs-common
  ansible.builtin.command: apt-get install -y nfs-common
  args:
    creates: /sbin/mount.nfs4

- name: Montage EFS
  ansible.posix.mount:
    path: /mnt/efs/hls
    src: "fs-0a8e1af25ce7ced67.efs.us-east-1.amazonaws.com:/"
    fstype: nfs4
    opts: "nfsvers=4.1,rsize=1048576,wsize=1048576,hard,timeo=600,retrans=2,noresvport,_netdev"
    state: mounted
```

**Différence :** Le montage `efs` avec TLS utilise un tunnel stunnel. Le montage `nfs4` est direct. Pour un lab, le NFS4 sans TLS est acceptable.

---

### Problème 8 : CloudFront → ALB → 301 redirect

**Symptôme :**
```bash
curl -I https://projet-streaming-ralph-steve.devops.intuitivelabs.net/hls/stream.m3u8
# HTTP/2 301
# location: https://gin208-alb-1135687834.us-east-1.elb.amazonaws.com:443/hls/stream.m3u8
```

**Cause :** CloudFront contacte l'ALB en HTTP (`origin_protocol_policy = "http-only"`). L'ALB avait un listener port 80 configuré en `redirect` vers HTTPS (301). CloudFront reçoit la 301 et la renvoie au client sans la suivre.

**Solution :** Changer le listener ALB port 80 de `redirect` vers `forward` dans `alb.tf` :
```hcl
# Avant :
default_action {
  type = "redirect"
  redirect {
    port        = "443"
    protocol    = "HTTPS"
    status_code = "HTTP_301"
  }
}

# Après :
default_action {
  type             = "forward"
  target_group_arn = aws_lb_target_group.frontend.arn
}
```

Puis `terraform apply`.

**Justification sécurité :** Le trafic client → CloudFront est HTTPS (enforced par `viewer_protocol_policy = "redirect-to-https"`). Le trafic CloudFront → ALB est HTTP dans le réseau AWS interne. Acceptable pour ce lab.

---

### Problème 9 : FFmpeg pousse vers une mauvaise IP

**Symptôme :** Le service `gin208-streamer` redémarre en boucle (active depuis 4ms à chaque check).

**Cause :** L'ASG a recyclé les instances Frontend. La nouvelle instance Frontend a l'IP `10.0.2.241`, mais le service FFmpeg était configuré pour pousser vers `10.0.2.243` (ancienne instance).

**Diagnostic :**
```bash
ansible role_streamer -m raw \
  -a "cat /etc/systemd/system/gin208-streamer.service" --become
# → ExecStart=... rtmp://10.0.2.243:1935/live/stream  ← mauvaise IP
```

**Solution :** Relancer `streamer.yml` qui recalcule dynamiquement l'IP :
```bash
ansible-playbook playbooks/streamer.yml
```
La variable `frontend_private_ip` est recalculée depuis l'inventaire dynamique :
```yaml
frontend_private_ip: "{{ hostvars[groups['role_frontend'][0]]['private_ip_address'] }}"
```

---

### Problème 10 : cloud-init status: error sur nouvelles instances

**Symptôme :**
```
status: error
```

**Cause :** Les nouvelles instances créées par l'ASG ont un `user_data` qui échoue (script de bootstrap partiellement exécuté). Résultat : `amazon-efs-utils` n'est pas installé, certains paquets peuvent manquer.

**Impact :** Le lock dpkg est parfois tenu pendant l'exécution du user_data. Commande pour attendre et ignorer l'erreur cloud-init :
```bash
ansible role_frontend -m raw \
  -a "cloud-init status --wait; apt-get install -y python3.9" --become
```
Le `;` (point-virgule) exécute `apt-get` même si `cloud-init --wait` retourne une erreur.

---

### Problème 11 : Credentials AWS expirés

**Symptôme :**
```
RequestExpired: Request has expired.
```

**Cause :** Les credentials AWS SSO de Télécom Paris expirent toutes les ~1 heure.

**Solution :** Renouveler depuis AWS CloudShell :
```bash
aws configure export-credentials --format env
# Copier-coller les 3 exports dans WSL
```

---

## 7. Flux de données complet <a name="flux"></a>

### 7.1 Chemin du flux vidéo

```
[FFmpeg - Streamer EC2]
  └─ génère testsrc 1280x720 + sine:440Hz
  └─ encode H.264/AAC (libx264 preset veryfast)
  └─ push RTMP → rtmp://10.0.2.241:1935/live/stream

[NGINX - Frontend EC2]
  └─ reçoit le flux RTMP sur port 1935
  └─ découpe en segments .ts de 2 secondes
  └─ génère playlist stream.m3u8 (fenêtre 10s = 5 segments)
  └─ écrit sur EFS : /mnt/efs/hls/stream.m3u8 + stream*.ts

[EFS - Stockage partagé]
  └─ accessible par toutes les instances Frontend de l'ASG
  └─ montage NFS4 sur /mnt/efs/hls

[ALB - Load Balancer]
  └─ reçoit GET /hls/stream.m3u8 depuis CloudFront (HTTP:80)
  └─ forward vers l'instance Frontend (port 80)

[NGINX - HTTP]
  └─ sert le fichier depuis /mnt/efs (root /mnt/efs + location /hls)
  └─ headers : Cache-Control: no-cache, Access-Control-Allow-Origin: *

[CloudFront]
  └─ reçoit les segments HLS (cache désactivé pour /hls/*)
  └─ transmet au navigateur
  └─ sert aussi index.html depuis S3

[Navigateur]
  └─ charge index.html (HLS.js player)
  └─ HLS.js requête stream.m3u8 toutes les 2s
  └─ télécharge les nouveaux segments .ts
  └─ décode et affiche la vidéo en continu
```

### 7.2 Chemin du health check ALB

```
[ALB] → GET / → HTTP:80 → [NGINX]
[NGINX] → return 200 'OK'
[ALB] → instance marquée healthy → trafic routé
```

Intervalle : 30s, seuil sain : 2 checks OK, seuil malade : 3 checks KO.

---

## 8. Commandes de référence <a name="commandes"></a>

### Terraform

```bash
cd ~/gin208/terraform

# Initialiser
terraform init

# Prévisualiser
terraform plan

# Appliquer
terraform apply

# Détruire (fin de projet)
terraform destroy

# Voir les outputs
terraform output
```

### Ansible

```bash
cd ~/gin208/ansible

# Tester la connectivité
ansible role_frontend -m ping
ansible role_streamer -m ping

# Lister les hôtes
ansible role_frontend --list-hosts

# Déployer Frontend (NGINX)
ansible-playbook playbooks/frontend.yml

# Déployer Streamer (FFmpeg)
ansible-playbook playbooks/streamer.yml

# Déployer CloudWatch Agent
ansible-playbook playbooks/cloudwatch-agent.yml

# Installer Python 3.9 (bootstrap manuel)
ansible role_frontend:role_streamer -m raw \
  -a "cloud-init status --wait; apt-get install -y python3.9" --become

# Vérifier statut d'un service
ansible role_streamer -m raw \
  -a "systemctl status gin208-streamer --no-pager" --become
```

### AWS CLI - Monitoring

```bash
# État des instances dans l'ALB
aws elbv2 describe-target-health \
  --target-group-arn $(aws elbv2 describe-target-groups \
    --query "TargetGroups[?contains(TargetGroupName,'gin208')].TargetGroupArn" \
    --output text) \
  --query "TargetHealthDescriptions[*].{ID:Target.Id,State:TargetHealth.State,Reason:TargetHealth.Reason}" \
  --output table

# Instances Frontend actives
aws ec2 describe-instances \
  --filters "Name=tag:Role,Values=frontend" "Name=instance-state-name,Values=running" \
  --query "Reservations[*].Instances[*].{ID:InstanceId,PrivateIP:PrivateIpAddress,PublicDNS:PublicDnsName}" \
  --output table

# Suspendre ASG pendant configuration
aws autoscaling suspend-processes \
  --auto-scaling-group-name gin208-asg-frontend \
  --scaling-processes HealthCheck ReplaceUnhealthy

# Réactiver ASG
aws autoscaling resume-processes \
  --auto-scaling-group-name gin208-asg-frontend \
  --scaling-processes HealthCheck ReplaceUnhealthy

# Vérifier les certificats ACM
aws acm list-certificates --region us-east-1 \
  --query "CertificateSummaryList[*].{Domain:DomainName,Status:Status}" \
  --output table

# Invalider le cache CloudFront
aws cloudfront create-invalidation \
  --distribution-id $(aws cloudfront list-distributions \
    --query "DistributionList.Items[?contains(Comment,'GIN208')].Id" \
    --output text) \
  --paths "/*"

# Uploader le player HTML
aws s3 cp ~/gin208/player.html \
  s3://gin208-player-708113109960/index.html --content-type "text/html"
```

### Tests fonctionnels

```bash
# Page principale (S3 via CloudFront)
curl -I https://projet-streaming-ralph-steve.devops.intuitivelabs.net/

# Flux HLS via CloudFront
curl -I https://projet-streaming-ralph-steve.devops.intuitivelabs.net/hls/stream.m3u8

# Flux HLS directement sur l'ALB (bypass CloudFront)
curl -Ik https://gin208-alb-1135687834.us-east-1.elb.amazonaws.com/hls/stream.m3u8

# Contenu de la playlist
curl -sk https://projet-streaming-ralph-steve.devops.intuitivelabs.net/hls/stream.m3u8
```

---

## 9. État actuel de l'infrastructure <a name="etat"></a>

### Ressources actives (juin 2026)

| Ressource | Identifiant | État |
|---|---|---|
| Instance Frontend | i-0e9560317ad44a8c7 (10.0.2.241) | Running, healthy ALB |
| Instance Streamer | ec2-32-197-201-148 (10.0.1.146) | Running, FFmpeg actif |
| EFS | fs-0a8e1af25ce7ced67 | Monté sur /mnt/efs/hls |
| ALB | gin208-alb-1135687834.us-east-1.elb.amazonaws.com | Actif |
| CloudFront | E3T4TPKB1DACBM | Déployé |
| S3 Player | gin208-player-708113109960 | index.html présent |
| VPC | vpc-05029c2c0922f940a | Actif |
| ASG | gin208-asg-frontend | desired=1, healthy |

### Outputs Terraform

```
alb_dns        = "gin208-alb-1135687834.us-east-1.elb.amazonaws.com"
app_url        = "https://projet-streaming-ralph-steve.devops.intuitivelabs.net"
cloudfront_url = "d1ji72m1eq00dv.cloudfront.net"
efs_id         = "fs-0a8e1af25ce7ced67"
```

### Points à noter pour la soutenance

1. **L'AMI utilisée est Ubuntu 20.04** (pas 22.04 comme prévu initialement). L'AMI `ami-0261755bbcb8c4a84` s'est révélée être Ubuntu 20.04 au runtime (Python 3.8 par défaut, GCC 9.4). Cela explique plusieurs problèmes Python.

2. **Le Streamer est dans le subnet public** (10.0.1.x), pas privé. Le subnet privé a été supprimé par simplification de l'architecture. Le Streamer n'a pas besoin d'être accessible de l'extérieur (pas d'ingress dans son SG), donc son placement dans un subnet public est acceptable.

3. **EFS monté en NFS4** (pas en `efs` avec TLS) suite à l'absence d'`amazon-efs-utils` dans les dépôts Ubuntu 20.04. Fonctionnellement équivalent pour ce lab.

4. **SSH utilisé pour Ansible** au lieu de SSM. Le SSM (Session Manager) nécessitait un rôle IAM sur les instances et une configuration réseau supplémentaire (endpoints VPC). Pour simplifier le déploiement dans le temps imparti, Ansible a utilisé SSH direct (port 22 ouvert dans la NACL, clé gin208-key).

5. **Credentials AWS temporaires** : les sessions AWS SSO expirent toutes les ~1h. En production réelle, on utiliserait des rôles IAM permanents sur les instances (instance profiles).
