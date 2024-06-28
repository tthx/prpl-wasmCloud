# wasmCLoud pour prplOS

## Installer le `LCM SDK for container application`
Suivre la procédure décrite dans le document [Installation and usage](https://espace.agir.orange.com/display/ECPRPL/Installation+and+usage).
* **ATTENTION**:
  - La version de la branche `main` du `sdk_helper` utilise, à ce jour, la version `4.0.1` de la SDK. Cette version n'a pas pu dépasser la partie `devtool build-image` du processus (cf. les erreurs ci-dessous). En utilisant la branche `v0.0.3`, qui utilise la version `3.0.0` de la SDK, nous avons pu finir la partie `devtool build-image`.
  - `wasmCloud` nécessite une version de Rust d'au moins `1.60.0`. Mais la version de Rust disponible avec la version `honister` de Yocto est la `1.54.0` et il n'est pas possible de la changer: [Rust on Yocto: A Seamless Integration](https://interrupt.memfault.com/blog/rust-in-yocto#meta-rust-bin), confirmé par:
    ```shell
    $ devtool upgrade rust
    NOTE: Starting bitbake server...
    NOTE: Reconnecting to bitbake server...
    NOTE: Retrying server connection (#1)...
    WARNING: You have included the meta-virtualization layer, but 'virtualization' has not been enabled in your DISTRO_FEATURES. Some bbappend files may not take effect. See the meta-virtualization README for details on enabling virtualization support.
    Loading cache: 100% |############################################| Time: 0:00:00
    Loaded 4870 entries from dependency cache.
    Parsing recipes: 100% |##########################################| Time: 0:00:00
    Parsing of 3496 .bb files complete (3495 cached, 1 parsed). 4871 targets, 351 skipped, 0 masked, 0 errors.

    Summary: There was 1 WARNING message shown.
    ERROR: rust is unavailable:
      rust was skipped: Rust recipe doesn't work for target builds at this time. Fixes welcome.
    ```
    Recherche de solution:
      * Construire une `prpl SDK` avec une version (>= `1.60.0`) de Rust: **impossible**, les *layers* développés par SoftAtHome (i.e. `containers`, `usp` et `amx`) ne supportent que la version `honister` de Yocto.
      * L'utilisation de [meta-rust](https://github.com/meta-rust/meta-rust) est impossible sur une architecture `x86_64`.
      * Utiliser [meta-rust-bin](https://github.com/rust-embedded/meta-rust-bin). **Ça a l'air de fonctionner...**
## Créer un registre local Docker
Sur la machine hôte
* Exécuter la fonction
  ```shell
  local_docker_registry() {
    local network_device="${1:-"${DEFAULT_NETWORK_DEVICE}"}";
    local etc_path="${2:-"${HOME}/etc"}";
    local certs_name="${3:-"docker-registry"}";
    local htpasswd_name="${4:-"htpasswd"}";
    local certs_size="${5:-"4096"}";
    local certs_days="${6:-"365"}";
    local registry_port="${7:-"5000"}";
    local login="${8:-"$(id -un)"}";
    local passwd="${9:-"${login}"}";
    local auth_path="${etc_path}/auth";
    local certs_path="${etc_path}/certs";
    local data_path="${etc_path}/data";

    if [ -n "$(docker container ls|awk '$2~/registry/')" ];
    then
      docker rm --force registry;
    fi
    sudo rm -rf "${etc_path}" && \
    mkdir -p "${etc_path}" && \
    mkdir -p "${auth_path}" "${certs_path}" "${data_path}" && \
    htpasswd -Bbc "${auth_path}/${htpasswd_name}" "${login}" "${passwd}" && \
    openssl req \
      -newkey rsa:"${certs_size}" \
      -nodes -keyout "${certs_path}/${certs_name}.key" \
      -out "${certs_path}/${certs_name}.csr" \
      -subj "/C=FR/ST=Paris/L=Paris/O=My Compagny/CN=$(get_ipaddr "${network_device}")" && \
    openssl x509 \
      -signkey "${certs_path}/${certs_name}.key" \
      -in "${certs_path}/${certs_name}.csr" \
      -req -days "${certs_days}" \
      -out "${certs_path}/${certs_name}.crt" \
      -extfile <(printf "subjectAltName=IP:$(get_ipaddr "${network_device}")") && \
    rm -f "${certs_path}/${certs_name}.csr" && \
    docker run -d --restart=always --name registry \
    -v "${auth_path}":"/auth" \
    -v "${certs_path}":"/certs" \
    -v "${data_path}":"/var/lib/registry" \
    -e REGISTRY_AUTH="htpasswd" \
    -e REGISTRY_AUTH_HTPASSWD_REALM="Registry Realm" \
    -e REGISTRY_AUTH_HTPASSWD_PATH="/auth/${htpasswd_name}" \
    -e REGISTRY_HTTP_ADDR="0.0.0.0:${registry_port}" \
    -e REGISTRY_HTTP_TLS_CERTIFICATE="/certs/${certs_name}.crt" \
    -e REGISTRY_HTTP_TLS_KEY="/certs/${certs_name}.key" \
    -p "${registry_port}":"${registry_port}" \
    registry:latest && \
    curl -u "${login}":"${passwd}" -k https://$(get_ipaddr "${network_device}"):${registry_port}/v2/_catalog;
    return $?;
  }
  ```
  **Note**:
    * La variable globale `DEFAULT_NETWORK_DEVICE` a été préalablement renseignée avec le nom d'une interface réseau. Voir ci-bas `network_device`.
    * Le certificat du registre local Docker est auto-signé: il n'a pas d'autorité de certification reconnue.
    * Le registre local Docker utilise HTTPS et écoute sur toutes les adresses IP et au port `5000`.
    * Pour la commande `htpasswd`, il faut installer, sur Ubuntu, le paquet `apache2-utils`.
    * Le couple `(user,passwd)` est positionné à `(${USER},${USER})`.
    * Le `subjectAltName` du certificat utilise une adresse IP. Cette adresse IP est celle du réseau local de l'hôte qui peut être obtenue par les commandes:
      ```shell
      get_ipaddr() {
        local errmsg="ERROR: ${FUNCNAME[0]}:";
        local network_device="${1:?"${errmsg} Missing network device (e.g.: enp0s31f6, enx381428d84cb8)"}";
        ip address show dev "${network_device}" | \
          awk '/inet /{split($2,x,"/"); printf("%s",x[1]);}';
      }
      ```
      Où `network_device` est le nom d'une interface réseau (e.g. `enx381428d84cb8`).
    * les fonctions `get_ipaddr` et `local_docker_registry` sont dans le script [local-docker-registry.sh](local-docker-registry.sh).
* Ajouter à `/etc/docker/daemon.json`
  ```
  "insecure-registries": ["$(get_ipaddr "${network_device}"):5000"],
  ```
  **Note**: Ici, nous nous restreignons à l'adresse IP au réseau local de l'hôte.
* Pour s'identifier au registre local Docker:
  ```shell
  docker login "$(get_ipaddr "${network_device}")":5000 -u "${USER}" -p "${USER}"
  ```
## Tests avec `rust-hello-world`
### Dans le container de `prpl SDK`
```shell
devtool modify rust-hello-world
devtool build rust-hello-world
devtool build-image
skopeo copy oci:/sdkworkdir/tmp/deploy/images/container-x86-64/image-lcm-container-minimal-container-x86-64-20240619082732.rootfs-oci docker://<@IP>:5000/rust-hello-world-x68_64:latest --dest-creds=<user>:<passwd> --dest-tls-verify=false
```
**Note**:
  * Nous avions utilisé `devtool modify rust-hello-world` et non `devtool add rust-hello-world https://gitlab.tech.orange/prpl-ware/hello-world-rust.git`, sinon, avec le `prpl SDK` `4.0.1`, nous aurions récupéré, lors de la commande `devtool build-image`, l'erreur:
    ```
    ERROR: image-lcm-container-minimal-1.0-r0 do_rootfs: Could not invoke dnf. Command '/sdkworkdir/tmp/work/container_cortexa53-oe-linux/image-lcm-container-minimal/1.0-r0/recipe-sysroot-native/usr/bin/dnf -v --rpmverbosity=info -y -c /sdkworkdir/tmp/work/container_cortexa53-oe-linux/image-lcm-container-minimal/1.0-r0/rootfs/etc/dnf/dnf.conf --setopt=reposdir=/sdkworkdir/tmp/work/container_cortexa53-oe-linux/image-lcm-container-minimal/1.0-r0/rootfs/etc/yum.repos.d --installroot=/sdkworkdir/tmp/work/container_cortexa53-oe-linux/image-lcm-container-minimal/1.0-r0/rootfs --setopt=logdir=/sdkworkdir/tmp/work/container_cortexa53-oe-linux/image-lcm-container-minimal/1.0-r0/temp --repofrompath=oe-repo,/sdkworkdir/tmp/work/container_cortexa53-oe-linux/image-lcm-container-minimal/1.0-r0/oe-rootfs-repo --setopt=install_weak_deps=False --nogpgcheck install hello-world-rust packagegroup-amx-core packagegroup-lcm-core packagegroup-ubus packagegroup-usp-endpoint' returned 1:
    DNF version: 4.8.0
    cachedir: /sdkworkdir/tmp/work/container_cortexa53-oe-linux/image-lcm-container-minimal/1.0-r0/rootfs/var/cache/dnf
    Added oe-repo repo from /sdkworkdir/tmp/work/container_cortexa53-oe-linux/image-lcm-container-minimal/1.0-r0/oe-rootfs-repo
    User-Agent: falling back to 'libdnf': could not detect OS or basearch
    repo: using cache for: oe-repo
    oe-repo: using metadata from Mon 13 May 2024 10:33:09 AM UTC.
    No match for argument: hello-world-rust
    Error: Unable to find a match: hello-world-rust

    ERROR: Logfile of failure stored in: /sdkworkdir/tmp/work/container_cortexa53-oe-linux/image-lcm-container-minimal/1.0-r0/temp/log.do_rootfs.447
    ERROR: Task (/sdkworkdir/layers/meta-lcm/meta-containers/recipes-core/images/image-lcm-container-minimal.bb:do_rootfs) failed with exit code '1'
    ```
  * Pour le premier lancement de la `prpl SDK` et pour la commande `devtool`, nous avions dû désactiver le réseau vers Orange: ils requièrent des accèdes à internet que le proxy de Orange ne permet pas.
Vérifier sur l'hôte:
```shell
curl -u "${USER}":"${USER}" -k https://$(get_ipaddr "${network_device}"):5000/v2/_catalog;
```
Le résultat la précédente commande devrait contenir `rust-hello-world-x68_64`. Par exemple:
```
{"repositories":["rust-hello-world-x68_64"]}
```
### Installer [Configure VM](https://espace.agir.orange.com/display/ECPRPL/Configure+VM)
**Note**: Lors du premier démarrage de la VM, il faut être connecté au réseau d'Orange (i.e. le VPN vers Orange est actif): apparemment, la VM récupère, par le réseau de Orange, des trucs et des machins non documentés. Sinon c'est le bordel...
* Vérifier le réseau de la VM
  ```shell
  root@prplOS:/# ip add
  1: lo: <LOOPBACK,UP,LOWER_UP> mtu 65535 qdisc noqueue state UNKNOWN group default qlen 1000
      link/loopback 00:00:00:00:00:00 brd 00:00:00:00:00:00
      inet 127.0.0.1/8 scope host lo
         valid_lft forever preferred_lft forever
      inet6 ::1/128 scope host
         valid_lft forever preferred_lft forever
  2: ip6tnl0@NONE: <NOARP> mtu 1452 qdisc noop state DOWN group default qlen 1000
      link/tunnel6 :: brd :: permaddr 9abe:5927:604b::
  3: eth0: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc fq_codel master br-lan state UP group default qlen 1000
      link/ether 08:00:27:eb:bb:61 brd ff:ff:ff:ff:ff:ff
  4: eth1: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc htb state UP group default qlen 1000
      link/ether 08:00:27:27:88:a2 brd ff:ff:ff:ff:ff:ff
      inet 192.168.0.17/24 scope global eth1
         valid_lft forever preferred_lft forever
      inet6 2a01:cb04:6e7:d800:a00:27ff:fe27:88a2/64 scope global dynamic mngtmpaddr
         valid_lft 1794sec preferred_lft 594sec
      inet6 fe80::a00:27ff:fe27:88a2/64 scope link
         valid_lft forever preferred_lft forever
  5: teql0: <NOARP> mtu 1500 qdisc noop state DOWN group default qlen 100
      link/void
  6: wlan0: <BROADCAST,MULTICAST> mtu 1500 qdisc noqueue state DOWN group default qlen 1000
      link/ether 5a:73:a7:5c:90:ba brd ff:ff:ff:ff:ff:ff permaddr 02:00:00:00:00:00
  7: wlan1: <BROADCAST,MULTICAST> mtu 1500 qdisc noqueue state DOWN group default qlen 1000
      link/ether 08:00:27:eb:bb:64 brd ff:ff:ff:ff:ff:ff permaddr 02:00:00:00:01:00
  8: hwsim0: <BROADCAST,MULTICAST> mtu 1500 qdisc noop state DOWN group default qlen 1000
      link/ieee802.11/radiotap 12:00:00:00:00:00 brd ff:ff:ff:ff:ff:ff
  9: br-lan: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc noqueue state UP group default qlen 1000
      link/ether f2:9a:a6:20:70:01 brd ff:ff:ff:ff:ff:ff
      inet 192.168.102.1/24 scope global br-lan
         valid_lft forever preferred_lft forever
      inet6 fe80::f09a:a6ff:fe20:7001/64 scope link
         valid_lft forever preferred_lft forever
  10: br-guest: <NO-CARRIER,BROADCAST,MULTICAST,UP> mtu 1500 qdisc noqueue state DOWN group default qlen 1000
      link/ether 5a:73:a7:5c:91:bc brd ff:ff:ff:ff:ff:ff
      inet 192.168.2.1/24 scope global br-guest
         valid_lft forever preferred_lft forever
  11: br-lcm: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc noqueue state UNKNOWN group default qlen 1000
      link/ether 5e:89:a6:03:90:09 brd ff:ff:ff:ff:ff:ff
      inet 192.168.5.1/24 scope global br-lcm
         valid_lft forever preferred_lft forever
  12: wlan0.1: <BROADCAST,MULTICAST> mtu 1500 qdisc noop master br-lan state DOWN group default qlen 1000
      link/ether 5a:73:a7:5c:91:bb brd ff:ff:ff:ff:ff:ff permaddr 02:00:00:00:00:00
  13: wlan0.2: <BROADCAST,MULTICAST> mtu 1500 qdisc noop master br-guest state DOWN group default qlen 1000
      link/ether 5a:73:a7:5c:91:bc brd ff:ff:ff:ff:ff:ff permaddr 02:00:00:00:00:00
  14: wlan0.3: <BROADCAST,MULTICAST> mtu 1500 qdisc noop master br-lan state DOWN group default qlen 1000
      link/ether 5a:73:a7:5c:91:bd brd ff:ff:ff:ff:ff:ff permaddr 02:00:00:00:00:00
  15: wlan0.4: <BROADCAST,MULTICAST> mtu 1500 qdisc noop master br-guest state DOWN group default qlen 1000
      link/ether 5a:73:a7:5c:91:be brd ff:ff:ff:ff:ff:ff permaddr 02:00:00:00:00:00
  ```
  et le routage réseau:
  ```shell
  root@prplOS:/# netstat -nr
  Kernel IP routing table
  Destination     Gateway         Genmask         Flags   MSS Window  irtt Iface
  0.0.0.0         192.168.0.1     0.0.0.0         UG        0 0          0 eth1
  192.168.0.0     0.0.0.0         255.255.255.0   U         0 0          0 eth1
  192.168.2.0     0.0.0.0         255.255.255.0   U         0 0          0 br-guest
  192.168.5.0     0.0.0.0         255.255.255.0   U         0 0          0 br-lcm
  192.168.102.0   0.0.0.0         255.255.255.0   U         0 0          0 br-lan
  ```
  et le contenu de `ubus`:
  ```shell
  root@prplOS:/# ubus-cli
  Copyright (c) 2020 - 2024 SoftAtHome
  amxcli version : 0.4.2

  !amx silent true

                     _  ___  ____
    _ __  _ __ _ __ | |/ _ \/ ___|
   | '_ \| '__| '_ \| | | | \___ \
   | |_) | |  | |_) | | |_| |___) |
   | .__/|_|  | .__/|_|\___/|____/
   |_|        |_| based on OpenWrt
   -----------------------------------------------------
   ubus - cli
   -----------------------------------------------------

   - ubus: - [ubus-cli] (0)
   > Device.SoftwareModules.ExecEnv.?
  Device.SoftwareModules.ExecEnv.1.
  Device.SoftwareModules.ExecEnv.1.ActiveExecutionUnits=""
  Device.SoftwareModules.ExecEnv.1.Alias="cpe-generic"
  Device.SoftwareModules.ExecEnv.1.AllocatedCPUPercent=100
  Device.SoftwareModules.ExecEnv.1.AllocatedDiskSpace=-1
  Device.SoftwareModules.ExecEnv.1.AllocatedMemory=-1
  Device.SoftwareModules.ExecEnv.1.AvailableDiskSpace=900728
  Device.SoftwareModules.ExecEnv.1.AvailableMemory=-1
  Device.SoftwareModules.ExecEnv.1.CreatedAt="2024-06-18T10:25:05.956272348Z"
  Device.SoftwareModules.ExecEnv.1.CurrentRunLevel=-1
  Device.SoftwareModules.ExecEnv.1.Description=""
  Device.SoftwareModules.ExecEnv.1.Enable=1
  Device.SoftwareModules.ExecEnv.1.InitialExecutionUnitRunLevel=-1
  Device.SoftwareModules.ExecEnv.1.InitialRunLevel=-1
  Device.SoftwareModules.ExecEnv.1.Name="generic"
  Device.SoftwareModules.ExecEnv.1.ParentExecEnv=""
  Device.SoftwareModules.ExecEnv.1.ProcessorRefList=""
  Device.SoftwareModules.ExecEnv.1.RestartReason=""
  Device.SoftwareModules.ExecEnv.1.Status="Up"
  Device.SoftwareModules.ExecEnv.1.Type="lxc:5.0.3"
  Device.SoftwareModules.ExecEnv.1.Vendor="Cthulhu"
  Device.SoftwareModules.ExecEnv.1.Version="3.5.1"
  Device.SoftwareModules.ExecEnv.1.Plugins.
  Device.SoftwareModules.ExecEnv.1.Plugins.DHCP.
  Device.SoftwareModules.ExecEnv.1.Plugins.DHCP.DefaultEnabled=1
  ```
* Vérifier que la machine virtuelle `prplOS` ne vérifie pas les autorités de certification (cf. [Build an application registry](https://espace.agir.orange.com/display/ECPRPL/Build+an+application+registry), section `Configure the gateway to deactivate certificate verification for older prplos version`):
  > Only feasible since 3.0.1 version of prplOS, with older versions, you will need to manage certificates to be real ones
  >
  >   * Modify the value "CertificateVerification" to 0 in /etc/amx/rlyeh/rlyeh_defaults.odl (you can use vi to do so).
  >   * Reboot the gateway with "reboot" command

  **Note**: Dans notre cas, `CertificateVerification` était déjà à `0`.
### Déployer `rust-hello-world` dans la VM prplOS
* Récupérer l'image de `rust-hello-world-x68_64:latest` du registre local Docker de l'hôte
```shell
root@prplOS:/# ubus-cli "SoftwareModules.InstallDU(URL ='docker://<@IP>:5000/rust-hello-world-x68_64:latest', Username = <user>, Password = <passwd>, ExecutionEnvRef = 'generic', UUID = 'd83bb790-c609-5ce3-a311-55fe58e3036b')"
> SoftwareModules.InstallDU(URL ='docker://<@IP>:5000/rust-hello-world-x6)
SoftwareModules.InstallDU() returned
[
  ""
]
```
Où:
  * `<@IP>` est l'adresse IP du registre local Docker de l'hôte,
  * `<user>` et `<passwd>` est le couple `(user,passwd)` (positionné à `(${USER},${USER})`) lors de la création du registre local Docker de l'hôte.
  * `d83bb790-c609-5ce3-a311-55fe58e3036b` est un UUID généré avec [UUID Generator](https://www.dcode.fr/uuid-identifier) à partir de la chaîne de caractères `rust-hello-world-x68_64:latest`.
* Vérifier que le container de `rust-hello-world` a été correctement installé
  ```shell
  root@prplOS:/# ubus-cli "SoftwareModules.DeploymentUnit.?" | grep d83bb790-c609-5ce3-a311-55fe58e3036b
  SoftwareModules.DeploymentUnit.2.UUID="d83bb790-c609-5ce3-a311-55fe58e3036b"
  ```
  Notez le numéro `2` du déploiement. Puis récupérer son `DUID`:
  ```shell
  root@prplOS:/# ubus-cli "SoftwareModules.DeploymentUnit.2.?" | grep DUID
  SoftwareModules.DeploymentUnit.2.DUID="901bb48f-c2f6-5cd3-b66d-155fc28e6eca"
  ```
  Enfin, vérifier que le `DUID` récupéré correspond à un container actif:
  ```shell
  root@prplOS:/# lxc-ls -f | grep 901bb48f-c2f6-5cd3-b66d-155fc28e6eca
  901bb48f-c2f6-5cd3-b66d-155fc28e6eca RUNNING 0         -      -    -    false
  ```
* Exécuter `rust-hello-world`
  ```shell
  root@prplOS:/# lxc-attach -n 901bb48f-c2f6-5cd3-b66d-155fc28e6eca
  root@901bb48f-c2f6-5cd3-b66d-155fc28e6eca:/# rust-hello-world
  Hello, world!
  ```
* Désinstaller `rust-hello-world-x68_64:latest`
  ```shell
  root@prplOS:/# ubus-cli 'SoftwareModules.DeploymentUnit.cpe-901bb48f-c2f6-5cd3-b66d-155fc28e6eca.Uninstall(RetainData = "No")'
  > SoftwareModules.DeploymentUnit.cpe-901bb48f-c2f6-5cd3-b66d-155fc28e6eca.Unins)
  SoftwareModules.DeploymentUnit.cpe-901bb48f-c2f6-5cd3-b66d-155fc28e6eca.Uninstad
  [
    ""
  ]
  ```
## wasmCloud/prplOS
Ce qui suit fonctionne pour la `prpl SDK` `3.0.0` et `4.0.1`.
### Des documents utiles
  * [Rust on Yocto: A Seamless Integration](https://interrupt.memfault.com/blog/rust-in-yocto)
  * [Using Rust with Yocto Project](https://www.konsulko.com/using-rust-with-yocto-project-by-paul-barker)
  * [Yocto Project Quick Build](https://docs.yoctoproject.org/brief-yoctoprojectqs/index.html), pour comprendre, un peu, le bordel...
### Dans la `prpl SDK`
#### Ajouter le *layer* [meta-rust-bin](https://github.com/rust-embedded/meta-rust-bin)
Nous fournissons le script [add-meta-rust-bin.sh](add-meta-rust-bin.sh) pour automatiser le processus:
  * Récupérer `meta-rust-bin`
    ```shell
    cd /sdkworkdir/layers
    git clone --recursive --depth=1 https://github.com/rust-embedded/meta-rust-bin.git
    ```
  * Ajouter `${SDKBASEMETAPATH}/layers/meta-rust-bin` au fichier `/sdkworkdir/conf/bblayers.conf`
  * Indiquer la version Rust à utiliser
    * Ajouter `require conf/rust.inc` au fichier `/sdkworkdir/conf/local.conf`
    * Créer le fichier `/sdkworkdir/conf/rust.inc` avec le contenu suivant
      ```
      RUST_VERSION ?= "1.79.0"
      RUSTVERSION ?= "${RUST_VERSION}"

      PREFERRED_VERSION_cargo ?= "${RUST_VERSION}"
      PREFERRED_VERSION_cargo-native ?= "${RUST_VERSION}"
      PREFERRED_VERSION_libstd-rs ?= "${RUST_VERSION}"
      PREFERRED_VERSION_rust ?= "${RUST_VERSION}"
      PREFERRED_VERSION_rust-cross-${TARGET_ARCH} ?= "${RUST_VERSION}"
      PREFERRED_VERSION_rust-llvm ?= "${RUST_VERSION}"
      PREFERRED_VERSION_rust-llvm-native ?= "${RUST_VERSION}"
      PREFERRED_VERSION_rust-native ?= "${RUST_VERSION}"
      ```
      où la variable `RUST_VERSION` indique la version voulue. Cette version doit être supportée par `meta-rust-bin`. Les versions de Rust supportées par sont indiquées dans [recipes-devtools/rust](https://github.com/rust-embedded/meta-rust-bin/tree/master/recipes-devtools/rust).

Le script [add-meta-rust-bin.sh](add-meta-rust-bin.sh) acceptent les paramètres, dans cet ordre:
  * `prpl_sdk_branch`, la branche `git` du `prpl SDK`, `main` par défaut,
  * `prpl_sdk_dir`, le répertoire Docker du `prpl SDK`, `"${HOME}/src/prpl-sdk/${prpl_sdk_branch}/x86/workspace` par défaut,
  * `rust_version`, la version de Rust, `1.79.0` par défaut.
#### Récupérer, éditer le fichier *recipe*, compiler et créer l'image du container de `wasmCloud`
Nous fournissons le script [wasmCloud-build.sh](wasmCloud-build.sh) pour automatiser le processus:
  - Récupérer `wasmCloud`
    ```shell
    $ devtool add wasmcloud -B release/v0.82.0 https://github.com/wasmCloud/wasmCloud.git
    ```
  - Éditer le fichier *recipe* de `wasmCloud`
    Par défaut, le fichier créé par le précédent `devtool add` est `/sdkworkdir/workspace/recipes/wasmcloud/wasmcloud_git.bb`. Il devrait contenir:
    ```
    inherit cargo_bin
    SUMMARY = "wasmCloud host runtime"
    HOMEPAGE = "https://github.com/wasmCloud/wasmCloud"
    LICENSE = "Apache-2.0"
    LIC_FILES_CHKSUM = "file://LICENSE;md5=398c810c4f475ff8ab49ba8d2ba614c1"
    SRC_URI = "git://github.com/wasmCloud/wasmCloud.git;protocol=https;branch=release/v0.82.0"
    PV = "1.0+git${SRCPV}"
    SRCREV = "9efb52976b4224aaece5fd430cd7e45ff4aa567c"
    S = "${WORKDIR}/git"
    # Enable network for the compile task allowing cargo to download dependencies
    do_compile[network] = "1"
    ```
  - Compiler et créer l'image du container de `wasmCloud`:
    ```shell
    $ devtool build wasmcloud
    $ devtool build-image
    ```

Le script [wasmCloud-build.sh](wasmCloud-build.sh) accepte comme paramètre une branche `git` de `wasmCloud`, `v0.82.0` par défaut.
#### Pousser l'image de `wasmCloud` dans le registre local Docker:
```shell
$ skopeo copy oci:/sdkworkdir/tmp/deploy/images/container-x86-64/image-lcm-container-minimal-container-x86-64-20240626105042.rootfs-oci docker://<@IP>:5000/wasmcloud-x68_64:v0.82.0 --dest-creds=<user>:<passwd> --dest-tls-verify=false
```
#### Dans la VM prplOS
* Récupérer l'image de `wasmcloud-x68_64:v0.82.0` du registre local Docker de l'hôte
  ```shell
  root@prplOS:/# ubus-cli "SoftwareModules.InstallDU(URL ='docker://<@IP>:5000/wasmcloud-x68_64:v0.82.0', Username = <user>, Password = <passwd>, ExecutionEnvRef = 'generic', UUID = '783bec3f-bb9d-5dc6-adad-eb2edc8d6d7d')"
  > SoftwareModules.InstallDU(URL ='docker://192.168.0.3:5000/wasmcloud-x68_64:v0)
  SoftwareModules.InstallDU() returned
  [
      ""
  ]
  ```
  **Note**: Pour le `UUID`, nous avons utilisé la chaîne `wasmcloud-x68_64:v0.82.0`.
* Vérifier que le container de `wasmcloud` a été correctement installé
  ```shell
  root@prplOS:/# ubus-cli "SoftwareModules.DeploymentUnit.?" | grep 783bec3f-bb9d-5dc6-adad-eb2edc8d6d7d
  SoftwareModules.DeploymentUnit.1.UUID="783bec3f-bb9d-5dc6-adad-eb2edc8d6d7d"
  ```
  Notez le numéro `1` du déploiement.
* Récupérer le `DUID` du container:
  ```shell
  root@prplOS:/# ubus-cli "SoftwareModules.DeploymentUnit.1.?" | grep DUID
  SoftwareModules.DeploymentUnit.1.DUID="16ce963a-c836-5e38-ab6e-9f9d08b71ceb"
  ```
* Vérifier que le `DUID` récupéré correspond à un container actif:
  ```shell
  root@prplOS:/# lxc-ls -f | grep 16ce963a-c836-5e38-ab6e-9f9d08b71ceb
  16ce963a-c836-5e38-ab6e-9f9d08b71ceb RUNNING 0         -      -    -    false
  ```
* Exécuter `wasmcloud`
  ```shell
  root@prplOS:/# lxc-attach -n 16ce963a-c836-5e38-ab6e-9f9d08b71ceb
  root@16ce963a-c836-5e38-ab6e-9f9d08b71ceb:/# wasmcloud
  Error: failed to initialize host

  Caused by:
      0: failed to establish NATS control server connection
      1: failed to connect to NATS
      2: IO error: Connection refused (os error 111)
  ```
## Une solution possible pour les versions de Yocto intégrant une version de Rust supérieure ou égale à 1.60.0 (pour espérer compiler wasmCloud)
### Créer le `bitbake`
#### Sur la machine hôte
* Installer `rust`
  ```shell
  curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh`
  ```
* Installer [cargo-bitbake](https://github.com/meta-rust/cargo-bitbake)
  ```shell
  cargo install --locked cargo-bitbake
  ```
  **Note**: sur `Ubuntu`, il faut installer, avant la précédente commande, le paquet `librust-cargo+openssl-dev`.
* Récupérer le code source de `wasmCloud`
  ```shell
  git clone https://github.com/wasmCloud/wasmCloud.git -b release/v0.82.0
  ```
* Comme `cargo-bitbake` utilise une ancienne syntaxe par rapport à celle utilisée par `wasmCloud` pour les `Cargo.toml`, il faut appliquer les patches via le script [wasmCloud-bitbake.sh](wasmCloud-bitbake.sh). Le script accepte les options:
  ```
  Usage: ./wasmCloud-bitbake.sh <get|apply|restore> [wasmCloud source dir] [patches dir]
  ```
  Où:
    * `get` crée les patches
    * `apply` applique les patches
    * `restore` met à l'origine le code source de `wasmCloud`
    * `wasmCloud source dir` est optionnel et a pour par défaut la valeur `${HOME}/src/wasmCloud}`
    * `patches dir` est optionnel et a pour par défaut la valeur `${HOME}/src/prpl-wasmCloud/wasmCloud`.
* Installer `wasmCloud`, dans le répertoire du code source de `wasmCloud`
  ```shell
  cargo update
  cargo install --path .
  ```
  **Note**: Par défaut, si ça se compile, le binaire `${HOME}/.cargo/bin/wasmcloud` est généré.
* Générer le `bitbake` de `wasmCloud`. Dans le répertoire du code source de `wasmCloud`:
  ```shell
  cargo bitbake
  ```
  **Note**: Par défaut, si ça se compile, le fichier `wasmcloud_0.82.0.bb` est généré dans le répertoire courant.
* Copier le code source de `wasmCloud` avec les patches appliqués dans le répertoire des sources de la `prpl SDK` utilisée (e.g. `${HOME}/src/prpl-sdk/main/x86/workspace/workspace/sources/wasmcloud`).
#### Dans `prpl SDK`
```shell
devtool add wasmcloud /sdkworkdir/workspace/sources/wasmcloud
cp /sdkworkdir/workspace/sources/wasmcloud/wasmcloud_0.82.0.bb /sdkworkdir/workspace/recipes/wasmcloud/wasmcloud_git.bb
devtool build wasmcloud
```
**Note**: l'option `--lcm_startup` existe pour la `prpl SDK` `3.0.0`, mais pas pour sa version `4.0.1`.
Et... Avec la version `honister` de Yocto, je me retrouve avec cet os:
```
| error: failed to select a version for the requirement `once_cell = "=1.18.0"`
| candidate versions found which didn't match: 1.17.2, 1.17.1, 1.17.0, ...
| location searched: crates.io index
| required by package `wasmcloud-actor v0.1.0 (/sdkworkdir/workspace/sources/wasmcloud/crates/actor)`
| WARNING: exit code 101 from a shell command.
ERROR: Task (/sdkworkdir/workspace/recipes/wasmcloud/wasmcloud_git.bb:do_compile) failed with exit code '1'
NOTE: Tasks Summary: Attempted 562 tasks of which 558 didn't need to be rerun and 1 failed.
```
La version minimale de [once_cell](https://crates.io/crates/once_cell/versions) acceptée par `wasmCloud` est la `1.18.0` qui requiert un compilateur Rust version `1.60.0`. Or la version de Rust fournie par le `prpl SDK` `4.0.1` est la `1.54.0`...
## Tests précédents

- Installer le `LCM SDK for container application` en suivant la procédure décrite dans le document [Installation and usage](https://espace.agir.orange.com/display/ECPRPL/Installation+and+usage)
  * **ATTENTION**: La version de la branche `main` du `sdk_helper` utilise, à ce jour, la version `4.0.1` de la SDK. Cette version n'a pas pu dépasser la partie `devtool build-image` du processus (cf. les erreurs ci-dessous). En utilisant la branche `v0.0.3`, qui utilise la version `3.0.0` de la SDK, nous avons pu finir la partie `devtool build-image`.

- Suivre la procédure [Manual code import in the SDK](https://gitlab.tech.orange/prpl-ware/samples/hello-world-rust#manual-code-import-in-the-sdk) de l'exemple [hello-world-rust](https://gitlab.tech.orange/prpl-ware/samples/hello-world-rust):

  * Lancer les commandes:
    ```shell
    cd /sdkworkdir/workspace/source
    git clone https://gitlab.tech.orange/prpl-ware/hello-world-rust.git
    devtool add hello-world-rust /sdkworkdir/workspace/source/hello-world-rust
    ```
  * Créer le fichier `/sdkworkdir/workspace/recipes/Cargo.toml`:
    ```
    inherit cargo

    SRC_URI = ""

    SUMMARY = "Hello World in rust"

    LICENSE = "CLOSED"
    LIC_FILES_CHKSUM = ""

    BBCLASSEXTEND = "native"
    ```
  * Compiler
    ```shell
    devtool build hello-world-rust
    devtool build-image
    ```
    Avec la version `4.0.1` de la SDK, la commande `devtool build-image` provoque cette erreur:
    ```
    ERROR: image-lcm-container-minimal-1.0-r0 do_rootfs: Could not invoke dnf. Command '/sdkworkdir/tmp/work/container_cortexa53-oe-linux/image-lcm-container-minimal/1.0-r0/recipe-sysroot-native/usr/bin/dnf -v --rpmverbosity=info -y -c /sdkworkdir/tmp/work/container_cortexa53-oe-linux/image-lcm-container-minimal/1.0-r0/rootfs/etc/dnf/dnf.conf --setopt=reposdir=/sdkworkdir/tmp/work/container_cortexa53-oe-linux/image-lcm-container-minimal/1.0-r0/rootfs/etc/yum.repos.d --installroot=/sdkworkdir/tmp/work/container_cortexa53-oe-linux/image-lcm-container-minimal/1.0-r0/rootfs --setopt=logdir=/sdkworkdir/tmp/work/container_cortexa53-oe-linux/image-lcm-container-minimal/1.0-r0/temp --repofrompath=oe-repo,/sdkworkdir/tmp/work/container_cortexa53-oe-linux/image-lcm-container-minimal/1.0-r0/oe-rootfs-repo --setopt=install_weak_deps=False --nogpgcheck install hello-world-rust packagegroup-amx-core packagegroup-lcm-core packagegroup-ubus packagegroup-usp-endpoint' returned 1:
    DNF version: 4.8.0
    cachedir: /sdkworkdir/tmp/work/container_cortexa53-oe-linux/image-lcm-container-minimal/1.0-r0/rootfs/var/cache/dnf
    Added oe-repo repo from /sdkworkdir/tmp/work/container_cortexa53-oe-linux/image-lcm-container-minimal/1.0-r0/oe-rootfs-repo
    User-Agent: falling back to 'libdnf': could not detect OS or basearch
    repo: using cache for: oe-repo
    oe-repo: using metadata from Mon 13 May 2024 10:33:09 AM UTC.
    No match for argument: hello-world-rust
    Error: Unable to find a match: hello-world-rust
    
    ERROR: Logfile of failure stored in: /sdkworkdir/tmp/work/container_cortexa53-oe-linux/image-lcm-container-minimal/1.0-r0/temp/log.do_rootfs.447
    ERROR: Task (/sdkworkdir/layers/meta-lcm/meta-containers/recipes-core/images/image-lcm-container-minimal.bb:do_rootfs) failed with exit code '1'
    ```
    
- Récupérer les sources de `wasmCloud`:
  ```shell
  cd /sdkworkdir/workspace/source
  git clone https://github.com/wasmCloud/wasmCloud.git
  devtool add wasmcloud /sdkworkdir/workspace/source/wasmCloud
  ```
- Retirer l'exemple `hello-world-rust`
  ```shell
  devtool reset hello-world-rust
  ```
- Editer le fichier `/sdkworkdir/workspace/recipes/Cargo.toml`:
  ```
  inherit cargo

  SRC_URI = ""

  SUMMARY = "wasmCloud"

  LICENSE = "CLOSED"
  LIC_FILES_CHKSUM = ""

  BBCLASSEXTEND = "native"
  ```
- Compiler
  ```shell
  devtool build wasmcloud
  devtool build-image
  ```
  Avec la version `4.0.1` de la SDK, la commande `devtool build-image` provoque cette erreur:
  ```
  ERROR: image-lcm-container-minimal-1.0-r0 do_rootfs: Could not invoke dnf. Command '/sdkworkdir/tmp/work/container_cortexa53-oe-linux/image-lcm-container-minimal/1.0-r0/recipe-sysroot-native/usr/bin/dnf -v --rpmverbosity=info -y -c /sdkworkdir/tmp/work/container_cortexa53-oe-linux/image-lcm-container-minimal/1.0-r0/rootfs/etc/dnf/dnf.conf --setopt=reposdir=/sdkworkdir/tmp/work/container_cortexa53-oe-linux/image-lcm-container-minimal/1.0-r0/rootfs/etc/yum.repos.d --installroot=/sdkworkdir/tmp/work/container_cortexa53-oe-linux/image-lcm-container-minimal/1.0-r0/rootfs --setopt=logdir=/sdkworkdir/tmp/work/container_cortexa53-oe-linux/image-lcm-container-minimal/1.0-r0/temp --repofrompath=oe-repo,/sdkworkdir/tmp/work/container_cortexa53-oe-linux/image-lcm-container-minimal/1.0-r0/oe-rootfs-repo --setopt=install_weak_deps=False --nogpgcheck install packagegroup-amx-core packagegroup-lcm-core packagegroup-ubus packagegroup-usp-endpoint wasmcloud' returned 1:
  DNF version: 4.8.0
  cachedir: /sdkworkdir/tmp/work/container_cortexa53-oe-linux/image-lcm-container-minimal/1.0-r0/rootfs/var/cache/dnf
  Added oe-repo repo from /sdkworkdir/tmp/work/container_cortexa53-oe-linux/image-lcm-container-minimal/1.0-r0/oe-rootfs-repo
  User-Agent: falling back to 'libdnf': could not detect OS or basearch
  repo: using cache for: oe-repo
  oe-repo: using metadata from Mon 13 May 2024 09:45:55 AM UTC.
  No match for argument: wasmcloud
  Error: Unable to find a match: wasmcloud
  ERROR: Logfile of failure stored in: /sdkworkdir/tmp/work/container_cortexa53-oe-linux/image-lcm-container-minimal/1.0-r0/temp/log.do_rootfs.476
  ERROR: Task (/sdkworkdir/layers/meta-lcm/meta-containers/recipes-core/images/image-lcm-container-minimal.bb:do_rootfs) failed with exit code '1'
  ```
- D'après le document [Installation](https://wasmcloud.com/docs/installation?os=source) de `wasmCloud`, il y est indiqué qu'il faut installer `wash-cli` plutôt que `wasmCloud`:
  ```shell
  cd /sdkworkdir/workspace/source
  devtool add wash-cli /sdkworkdir/workspace/source/wasmCloud/crates/wash-cli
  ```
- Editer le fichier `/sdkworkdir/workspace/recipes/Cargo.toml`:
  ```
  inherit cargo

  SRC_URI = ""

  SUMMARY = "wash-cli"

  LICENSE = "CLOSED"
  LIC_FILES_CHKSUM = ""

  BBCLASSEXTEND = "native"
  ```
- Retirer l'exemple `wasmcloud`
  ```shell
  devtool reset wasmcloud
  ```
- Compiler
  ```shell
  devtool build wash-cli
  devtool build-image
  ```
  Avec la version `4.0.1` de la SDK, la commande `devtool build-image` provoque cette erreur:
  ```
  ERROR: image-lcm-container-minimal-1.0-r0 do_rootfs: Could not invoke dnf. Command '/sdkworkdir/tmp/work/container_cortexa53-oe-linux/image-lcm-container-minimal/1.0-r0/recipe-sysroot-native/usr/bin/dnf -v --rpmverbosity=info -y -c /sdkworkdir/tmp/work/container_cortexa53-oe-linux/image-lcm-container-minimal/1.0-r0/rootfs/etc/dnf/dnf.conf --setopt=reposdir=/sdkworkdir/tmp/work/container_cortexa53-oe-linux/image-lcm-container-minimal/1.0-r0/rootfs/etc/yum.repos.d --installroot=/sdkworkdir/tmp/work/container_cortexa53-oe-linux/image-lcm-container-minimal/1.0-r0/rootfs --setopt=logdir=/sdkworkdir/tmp/work/container_cortexa53-oe-linux/image-lcm-container-minimal/1.0-r0/temp --repofrompath=oe-repo,/sdkworkdir/tmp/work/container_cortexa53-oe-linux/image-lcm-container-minimal/1.0-r0/oe-rootfs-repo --setopt=install_weak_deps=False --nogpgcheck install packagegroup-amx-core packagegroup-lcm-core packagegroup-ubus packagegroup-usp-endpoint wash-cli' returned 1:
  DNF version: 4.8.0
  cachedir: /sdkworkdir/tmp/work/container_cortexa53-oe-linux/image-lcm-container-minimal/1.0-r0/rootfs/var/cache/dnf
  Added oe-repo repo from /sdkworkdir/tmp/work/container_cortexa53-oe-linux/image-lcm-container-minimal/1.0-r0/oe-rootfs-repo
  User-Agent: falling back to 'libdnf': could not detect OS or basearch
  repo: using cache for: oe-repo
  oe-repo: using metadata from Tue 14 May 2024 08:22:04 AM UTC.
  No match for argument: wash-cli
  Error: Unable to find a match: wash-cli
  
  ERROR: Logfile of failure stored in: /sdkworkdir/tmp/work/container_cortexa53-oe-linux/image-lcm-container-minimal/1.0-r0/temp/log.do_rootfs.2050
  ERROR: Task (/sdkworkdir/layers/meta-lcm/meta-containers/recipes-core/images/image-lcm-container-minimal.bb:do_rootfs) failed with exit code '1'
  ```
- Pousser l'image dans un registre Docker
  * Sur l'hôte
    - Installer un registre local Docker
      ```shell
      local_docker_registry() {
        local etc_path="${HOME}/etc";
        local auth_path="${etc_path}/auth";
        local certs_path="${etc_path}/certs";
        local data_path="${etc_path}/data";
        local certs_name="docker-registry";
        local htpasswd_name="htpasswd";
        local certs_size="4096";
        local certs_days="365";
        local registry_port="5000";
      
        mkdir -p "${auth_path}" "${certs_path}" && \
        htpasswd -Bbc "${auth_path}/${htpasswd_name}" "${USER}" "${USER}" && \
        openssl req \
          -newkey rsa:"${certs_size}" \
          -nodes -keyout "${certs_path}/${certs_name}.key" \
          -out "${certs_path}/${certs_name}.csr" \
          -subj "/C=FR/ST=Paris/L=Paris/O=My Compagny/CN=$(get_ipaddr "${network_device}")" && \
        openssl x509 \
          -signkey "${certs_path}/${certs_name}.key" \
          -in "${certs_path}/${certs_name}.csr" \
          -req -days "${certs_days}" \
          -out "${certs_path}/${certs_name}.crt" \
          -extfile <(printf "subjectAltName=IP:$(get_ipaddr "${network_device}")") && \
        rm -f "${certs_path}/${certs_name}.csr" && \
        docker rm --force registry && \
        docker run -d --restart=always --name registry \
        -v "${auth_path}":"/auth" \
        -v "${certs_path}":"/certs" \
        -v "${data_path}":"/var/lib/registry" \
        -e REGISTRY_AUTH="htpasswd" \
        -e REGISTRY_AUTH_HTPASSWD_REALM="Registry Realm" \
        -e REGISTRY_AUTH_HTPASSWD_PATH="/auth/${htpasswd_name}" \
        -e REGISTRY_HTTP_ADDR="0.0.0.0:${registry_port}" \
        -e REGISTRY_HTTP_TLS_CERTIFICATE="/certs/${certs_name}.crt" \
        -e REGISTRY_HTTP_TLS_KEY="/certs/${certs_name}.key" \
        -p "${registry_port}":"${registry_port}" \
        registry:latest && \
        curl -u "${USER}":"${USER}" -k https://$(get_ipaddr "${network_device}"):${registry_port}/v2/_catalog;
        return $?;
      }
      ```
      **Note**:
        * Le certificat du registre local Docker est auto-signé: il n'a pas d'autorité de certification reconnue.
        * Le registre local Docker utilise HTTPS et écoute sur toutes les adresses IP et au port `5000`.
        * Pour la commande `htpasswd`, il faut installer, sur Ubuntu, le paquet `apache2-utils`.
        * Le couple `(login,passwd)` est positionné à `(${USER},${USER})`.
        * Le `subjectAltName` du certificat utilise une adresse IP. Cette adresse IP est celle du réseau local de l'hôte qui peut être obtenue par les commandes:
          ```shell
          get_ipaddr() {
            local errmsg="ERROR: ${FUNCNAME[0]}:";
            local dev="${1:?"${errmsg} Missing network device (e.g.: enp0s31f6, enx381428d84cb8)"}";
            ip address show dev "${dev}" | \
              awk '/inet /{split($2,x,"/"); printf("%s",x[1]);}';
          }
          ```
          Où `network_device` est le nom d'une interface réseau (e.g. `enx381428d84cb8`).
    - Ajouter à `/etc/docker/daemon.json`
      ```
      "insecure-registries": ["$(get_ipaddr "${network_device}"):5000"],
      ```
      **Note**: Ici, nous nous restreignons à l'adresse IP au réseau local de l'hôte.
    - Pour s'identifier au registre local Docker:
      ```shell
      docker login "$(get_ipaddr "${network_device}")":5000 -u "${USER}" -p "${USER}"
      ```
  * Dans le container où `wash-cli` a été compilé et l'image Docker en a été créée, exécuter la commande:
    ```shell
    skopeo copy oci:/sdkworkdir/tmp/deploy/images/container-x86-64/image-lcm-amx-ubus-usp-lcmsampleapp-container-x86-64-20240514094636.rootfs-oci docker://<@IP du registre local Docker de l'hôte>:5000/<imagename>:<imageversion> --dest-creds=<username>:<passwd> --dest-tls-verify=false
    ```
    Où:
      * `@IP du registre local Docker de l'hôte` est le résultat, sur l'hôte, de la commande:
        ```shell
        get_ipaddr "${network_device}"
        ```
      * `imagename` est le nom donné arbitrairement à l'image Docker (e.g. `prpl-wash-cli-x86`)
      * `imageversion` est le nom donné arbitrairement à la version de l'image Docker (e.g. `latest`)
      * `username` et `passwd` sont les valeurs du couple `(username, passwd)` pour le registre local Docker créé précédemment.
    **Note**: L'option `--dest-tls-verify=false` est nécessaire car le certificat du registre local Docker n'a pas d'autorité de certification reconnue.
  * Sur l'hôte, vérifier la présence de l'image précédemment poussée dans le registre local Docker par la commande:
    ```shell
    curl -k -u <username>:<passwd> -X GET http://"$(get_ipaddr "${network_device}")":5000/v2/_catalog
    ```
    Dont le résultat devrait contenir le nom `imagename`. Par exemple:
    ```
    {"repositories":["busybox","prpl-wash-cli-x86"]}
    ```
- Installer ça: [Configure VM](https://espace.agir.orange.com/display/ECPRPL/Configure+VM)
  * Configurer le réseau de la machine virtuelle (merci à [Running prplOS on Virtual Box](https://routerarchitects.com/blog-prplos/), et bonjour le support d'experts des chiottes). Dans `minicom`:
    * Au fichier `/etc/config/network`, ajouter les lignes:
      ```
      config interface 'eth0'
        option ifname 'eth0'
        option proto 'dhcp
      config interface 'eth1'
        option ifname 'eth1'
        option proto 'dhcp
      ```
    * Relancer le réseau:
      ```shell
      root@prplOS:/# /etc/init.d/network restart
      ```
    * Vérifier les adresses IP des interfaces `eth0` et `eth1`:
      * `eth0`:
        ```shell
        root@prplOS:/# ip address show dev eth0                                         
        3: eth0: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc fq_codel state UP gro0
            link/ether 08:00:27:8e:27:25 brd ff:ff:ff:ff:ff:ff                          
            inet 10.0.2.15/24 brd 10.0.2.255 scope global eth0                          
               valid_lft forever preferred_lft forever                                  
            inet6 fe80::a00:27ff:fe8e:2725/64 scope link                                
               valid_lft forever preferred_lft forever
        ```
      * `eth1`:
        ```shell
        root@prplOS:/# ip address show dev eth1                                         
        4: eth1: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc htb state UP group de0
            link/ether 08:00:27:67:c3:e9 brd ff:ff:ff:ff:ff:ff                          
            inet 192.168.0.4/24 brd 192.168.0.255 scope global eth1                     
               valid_lft forever preferred_lft forever                                  
            inet6 fe80::a00:27ff:fe67:c3e9/64 scope link                                
               valid_lft forever preferred_lft forever
        ```
    * Modifier les règles du firewall:
      ```shell
      iptables -F
      iptables -P INPUT ACCEPT
      iptables -P FORWARD ACCEPT
      iptables -P OUTPUT ACCEPT
      ```
    * Vérifier l'accès de la machine virtuelle prplOS au registre local Docker:
      ```shell
      root@prplOS:/# curl -k -u <username>:<passwd> -X GET https://<@IP du registre local Docker de l'hôte>:5000/v2/_catalog
      {"repositories":["prpl-wash-cli-arm","prpl-wash-cli-x86"]}
      ```
- Vérifier que la machine virtuelle `prplOS` ne vérifie pas les autorités de certification (cf. [Build an application registry](https://espace.agir.orange.com/display/ECPRPL/Build+an+application+registry), section `Configure the gateway to deactivate certificate verification for older prplos version`):
  > Only feasible since 3.0.1 version of prplOS, with older versions, you will need to manage certificates to be real ones
  >
  >   * Modify the value "CertificateVerification" to 0 in /etc/amx/rlyeh/rlyeh_defaults.odl (you can use vi to do so).
  >   * Reboot the gateway with "reboot" command
  
  **Note**: Dans notre cas, `CertificateVerification` était déjà à `0`.
- Dans `minicom`, exécuter la commande:
  ```shell
  root@prplOS:/# ubus-cli "SoftwareModules.InstallDU(URL ='docker://<@IP du registre local Docker de l'hôte>:5000/prpl-wash-cli-x86:latest', Username = <username>, Password = <passwd>, ExecutionEnvRef = 'generic', UUID = 'adc12c26-c60b-57b4-94b8-3eebf1bd076a')"
  ```

  **Note**: Pour générer le `UUID` avec la chaîne de caractères `prpl-wash-cli-x86:latest`, j'ai utilisé ça: [UUID Generator](https://www.dcode.fr/uuid-identifier)

  Mais ça tombe sur cet os:
  ```
  ERROR: call (null) failed with status 18
  SoftwareModules.InstallDU() returned
  [
      "",
      {
          DUID = "57b6d4e6-4bf7-5412-a333-523573902103",
          err_code = 7223,
          err_msg = "Unknown Execution Environment"
      }
  ]
  ```

  D'après le document [LCM SDK - Introduction and howto v2](https://espace.agir.orange.com/display/ECPRPL/LCM+SDK+-+SAH+Documentation?preview=%2F1205049791%2F1205049798%2FLCM+SDK+-+Introduction+and+howto+v2.pdf&searchId=OGDVUB153), le document est très incomplet mais donne des indices sur les points manquants. D'après le document de [SoftwareModules.InstallDU](https://usp-data-models.broadband-forum.org/tr-181-2-16-0-usp.html#D.Device:2.Device.SoftwareModules.InstallDU), la valeur de [ExecutionEnvRef](https://usp-data-models.broadband-forum.org/tr-181-2-16-0-usp.html#D.Device:2.Device.SoftwareModules.InstallDU.Input.ExecutionEnvRef) devrait satisfaire:

  > The value MUST be the Path Name of a row in the [ExecEnv](https://usp-data-models.broadband-forum.org/tr-181-2-16-0-usp.html#D.Device:2.Device.SoftwareModules.ExecEnv.). table. A reference to the Execution Environment upon which the DU is to be installed.
  >
  > If an empty string the device MUST choose the Execution Environment to use.

  Et [ExecEnv](https://usp-data-models.broadband-forum.org/tr-181-2-16-0-usp.html#D.Device:2.Device.SoftwareModules.ExecEnv.) :

  > The Execution Environments that are available on the device, along with their properties and configurable settings.
  >
  > At most one entry in this table can exist with a given value for Alias, or with a given value for Name.
  
  De ce que je comprends, la VM fournis devrait renseigner `ExecEnv`, or, dans la VM, dans la commande `ubus-cli`:

  ```
   - ubus: - [ubus-cli] (0)                                                       
   > Device.SoftwareModules.ExecEnv.?                                             
  No data found 
  ```

  Le document "LCM SDK - Introduction and howto v2", le plus utile que j'ai trouvé, indique vaquement comment créer les "repices" et les "services".
  
