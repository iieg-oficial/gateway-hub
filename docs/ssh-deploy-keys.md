# SSH Deploy Keys — Configuración Multi-Repo

## Estructura

```
~/.ssh/
├── config              # Hosts SSH por repo
├── github_gateway      # Key privada → iieg-oficial/gateway-hub
├── github_gateway.pub
├── github_acervo       # Key privada → iieg-oficial/acervo
└── github_acervo.pub
```

## ~/.ssh/config

```
Host github
    HostName github.com
    User git
    IdentityFile ~/.ssh/github_gateway
    IdentitiesOnly yes

Host github_acervo
    HostName github.com
    User git
    IdentityFile ~/.ssh/github_acervo
    IdentitiesOnly yes
```

## Remotes

```bash
# gateway-hub
git remote set-url origin git@github:iieg-oficial/gateway-hub.git

# acervo
git remote set-url origin git@github_acervo:iieg-oficial/acervo.git
```

## Generar keys nuevas (si se pierden)

```bash
ssh-keygen -t ed25519 -f ~/.ssh/github_gateway -C "gateway-hub-deploy-key" -N ""
ssh-keygen -t ed25519 -f ~/.ssh/github_acervo -C "acervo-deploy-key" -N ""
```

Agregar cada `.pub` en GitHub → Repo → Settings → Deploy keys.

## Proteger archivos

```bash
chmod 700 ~/.ssh
chmod 600 ~/.ssh/config ~/.ssh/github_gateway ~/.ssh/github_acervo
chmod 644 ~/.ssh/github_gateway.pub ~/.ssh/github_acervo.pub
sudo chattr +i ~/.ssh/github_gateway ~/.ssh/github_gateway.pub
sudo chattr +i ~/.ssh/github_acervo ~/.ssh/github_acervo.pub
sudo chattr +i ~/.ssh/config
```

Para desbloquear: `sudo chattr -i <archivo>`

## Verificar

```bash
ssh -T git@github          # → Hi iieg-oficial/gateway-hub!
ssh -T git@github_acervo   # → Hi iieg-oficial/acervo!
```
