# Runner de CI no PC (Docker)

Passo a passo para o Luis (Windows):

1. Instale o **Docker Desktop** (https://www.docker.com/products/docker-desktop/) com a opção **WSL 2** marcada. Reinicie se pedir.
2. No GitHub, crie um token em *Settings > Developer settings > Fine-grained tokens*:
   - Repositório: só `gd-vn-studio`.
   - Permissão do repositório: **Administration: Read and write** (é o que permite registrar runners). Nada além disso.
   - Validade: 90 dias.
3. Na pasta do projeto, entre em `.github\runner`, copie `.env.example` para `.env` e cole o token em `GITHUB_PAT=`.
4. Suba o runner: `docker compose up -d --build` (use `--scale runner=2` para dois jobs em paralelo).
5. Confira em *Settings > Actions > Runners*: deve aparecer `pc-luis-…` como **Idle**.
6. Configure o Docker Desktop para iniciar com o Windows (*Settings > General > Start Docker Desktop when you sign in*). Os contêineres têm `restart: always` e voltam sozinhos.

Segurança:
- Só em repositório **privado**. Em *Settings > Actions > General*, deixe *Fork pull request workflows* desligado.
- Cada job roda num contêiner descartável, sem acesso às pastas do PC, ao `docker.sock` nem a privilégios extras.
- O `.env` com o token nunca vai para o Git. Para parar tudo: `docker compose down`.
- Windows e macOS não rodam aqui; os jobs desses sistemas ficaram de fora da CI por enquanto.
