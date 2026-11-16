#!/usr/bin/env python3
# =============================================================================
# publicar_github.py
#
# Publica el CODIGO de este repositorio en GitHub **sin subir los .md**.
#
# Por que existe: la documentacion (AGENTS.md, CRONOGRAMA.md, manual, planes y
# specs) se queda en el equipo local; el repositorio remoto es solo codigo. El
# historial local no se toca: en cada publicacion se crea UN commit sobre la
# rama remota (main) cuyo arbol es el del HEAD local con los .md fuera. Asi el
# PR de cada entrega muestra exactamente lo que cambio en el codigo.
#
# Uso (desde la raiz del repo):
#   python deploy/publicar_github.py --dry-run          # ver que haria
#   python deploy/publicar_github.py                    # empuja 'entrega' y abre/actualiza el PR
#   python deploy/publicar_github.py --rama entrega2 --sin-pr
#   python deploy/publicar_github.py --mensaje "Mi cambio"
#
# Requiere: git con credencial guardada para github.com (Git Credential
# Manager) y la libreria estandar. No imprime el token.
#
# Que NO hace: no empuja main, no toca el historial local, no borra nada del
# repositorio remoto. Los .md jamas se copian al area de trabajo temporal.
# =============================================================================

import argparse
import json
import os
import shutil
import subprocess
import sys
import tempfile
import urllib.error
import urllib.request

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
URL = "https://github.com/luismiromi84-ai/apex.git"
REPO_API = "luismiromi84-ai/apex"
TITULO_POR_DEFECTO = "Publicar codigo (sin documentacion)"


def git(*args, cwd=None, check=True):
    r = subprocess.run(["git", *args], cwd=cwd or REPO, capture_output=True, text=True,
                       encoding="utf-8", errors="replace")
    if check and r.returncode != 0:
        raise SystemExit("git %s fallo:\n%s\n%s" % (" ".join(args), r.stdout, r.stderr))
    return r


def archivos_del_head():
    """Rutas del HEAD local, sin los .md."""
    salida = git("ls-tree", "-r", "-z", "--name-only", "HEAD").stdout
    return [a for a in salida.split("\0") if a and not a.lower().endswith(".md")]


def token_github():
    r = subprocess.run(["git", "credential", "fill"],
                       input="protocol=https\nhost=github.com\n\n",
                       capture_output=True, text=True)
    for linea in r.stdout.splitlines():
        if linea.startswith("password="):
            return linea.split("=", 1)[1]
    return None


def api(metodo, url, cuerpo, token):
    datos = json.dumps(cuerpo).encode() if cuerpo is not None else None
    req = urllib.request.Request(url, method=metodo, data=datos)
    req.add_header("Authorization", "Bearer " + token)
    req.add_header("Accept", "application/vnd.github+json")
    req.add_header("X-GitHub-Api-Version", "2022-11-28")
    if datos:
        req.add_header("Content-Type", "application/json")
    with urllib.request.urlopen(req, timeout=60) as r:
        return json.loads(r.read().decode())


def pr_abierto(rama, token):
    """PR abierto de esta rama, si ya existe (para no duplicarlo)."""
    try:
        lista = api("GET", "https://api.github.com/repos/%s/pulls?state=open&head=%s:%s"
                    % (REPO_API, REPO_API.split("/")[0], rama), None, token)
        return lista[0] if lista else None
    except Exception:
        return None


def main():
    ap = argparse.ArgumentParser(description="Publica el codigo en GitHub sin los .md.")
    ap.add_argument("--rama", default="entrega", help="rama remota a la que empujar (por defecto entrega)")
    ap.add_argument("--base", default="main", help="rama base del PR (por defecto main)")
    ap.add_argument("--mensaje", default="Publicar codigo desde el equipo local (sin .md)")
    ap.add_argument("--titulo", default=TITULO_POR_DEFECTO)
    ap.add_argument("--cuerpo", default=None, help="archivo con el cuerpo del PR (opcional)")
    ap.add_argument("--sin-pr", action="store_true", help="empujar la rama y no abrir PR")
    ap.add_argument("--dry-run", action="store_true", help="solo informar, no empujar")
    args = ap.parse_args()

    if git("status", "--porcelain").stdout.strip():
        print("[aviso] hay cambios sin commitear: se publica el HEAD (lo commiteado), no el arbol sucio.")

    rutas = archivos_del_head()
    if not rutas:
        raise SystemExit("no hay archivos en HEAD: nada que publicar")
    print("archivos a publicar: %d (sin .md)" % len(rutas))

    tmp = os.path.join(tempfile.gettempdir(), "opencode", "publicar-github")
    if os.path.isdir(tmp):
        shutil.rmtree(tmp, ignore_errors=True)
    os.makedirs(tmp, exist_ok=True)

    git("init", "-q", cwd=tmp)
    git("remote", "add", "origin", URL, cwd=tmp)
    print("bajando %s..." % args.base)
    git("fetch", "-q", "origin", args.base, cwd=tmp)
    git("reset", "-q", "--hard", "FETCH_HEAD", cwd=tmp)

    # Dejar el arbol temporal EXACTAMENTE como el HEAD local, sin .md.
    for raiz, dirs, ficheros in os.walk(tmp):
        if ".git" in dirs:
            dirs.remove(".git")
        for f in ficheros:
            os.remove(os.path.join(raiz, f))
    copiados = 0
    for rel in rutas:
        ruta_git = rel.replace("\\", "/")
        # Se escribe el contenido del HEAD (el blob), no el byte del arbol de
        # trabajo: si hay cambios sin commitear, se publica lo commiteado.
        blob = subprocess.run(["git", "show", "HEAD:" + ruta_git], cwd=REPO,
                              capture_output=True)
        if blob.returncode != 0:
            raise SystemExit("no pude leer HEAD:%s" % ruta_git)
        destino = os.path.join(tmp, rel.replace("/", os.sep))
        os.makedirs(os.path.dirname(destino) or tmp, exist_ok=True)
        with open(destino, "wb") as f:
            f.write(blob.stdout)
        copiados += 1
    print("copiados: %d" % copiados)

    git("add", "-A", cwd=tmp)
    if git("diff", "--cached", "--quiet", cwd=tmp, check=False).returncode == 0:
        print("NADA NUEVO: el codigo de %s ya es el de este equipo." % args.base)
        return 0

    nombre = git("config", "user.name", check=False).stdout.strip() or "Synpex"
    correo = git("config", "user.email", check=False).stdout.strip() or "synpex@local"
    git("-c", "user.name=" + nombre, "-c", "user.email=" + correo,
        "commit", "-q", "-m", args.mensaje, cwd=tmp)
    resumen = git("show", "--stat", "--oneline", "HEAD", cwd=tmp).stdout.strip().splitlines()
    print("\n".join(resumen[-6:]))

    if args.dry_run:
        print("\n[dry-run] no se empuja nada.")
        return 0

    print("empujando a %s..." % args.rama)
    git("push", "-f", "origin", "HEAD:refs/heads/%s" % args.rama, cwd=tmp)

    if args.sin_pr:
        print("rama %s publicada (sin PR)." % args.rama)
        return 0

    token = token_github()
    if not token:
        print("no encontre credencial para la API: abre el PR a mano en")
        print("https://github.com/%s/compare/%s...%s?expand=1" % (REPO_API, args.base, args.rama))
        return 1

    cuerpo = "Publicacion del codigo del equipo local. Los `.md` no se suben."
    if args.cuerpo and os.path.exists(args.cuerpo):
        with open(args.cuerpo, encoding="utf-8") as f:
            cuerpo = f.read()

    existente = pr_abierto(args.rama, token)
    if existente:
        print("PR ya abierto (actualizado):", existente["html_url"])
        return 0

    try:
        pr = api("POST", "https://api.github.com/repos/%s/pulls" % REPO_API,
                 {"title": args.titulo, "head": args.rama, "base": args.base, "body": cuerpo}, token)
        print("PR:", pr["html_url"])
    except urllib.error.HTTPError as ex:
        print("no se pudo abrir el PR (%s): %s" % (ex.code, ex.read().decode()[:300]))
        print("abrelo a mano en https://github.com/%s/compare/%s...%s?expand=1"
              % (REPO_API, args.base, args.rama))
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
