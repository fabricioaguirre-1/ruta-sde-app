# rodMap: busca una versión nueva en GitHub, la instala si existe y abre la app.
# El repositorio de la app es privado: para descargarlo se usa un token de solo lectura guardado
# en la variable de entorno del usuario RUTASDE_TOKEN (se crea una vez con setx; nunca va en un archivo).
# Si no hay internet, no hay token o algo falla, abre la versión que ya está en la computadora.
# rodMap-lanzador v3: también se actualiza a sí mismo, el ícono y el nombre de los accesos directos.
# El ícono se guarda con un nombre nuevo cada vez que cambia (rodmap-xxxxxxxx.ico): Windows guarda en caché
# los íconos por ruta, así que cambiar el archivo sin cambiar la ruta deja el logo viejo en el escritorio.
$ErrorActionPreference = 'SilentlyContinue'
$dir  = $PSScriptRoot
$app  = Join-Path $dir 'ruta-sde.html'
$verF = Join-Path $dir 'version.txt'
$log  = Join-Path $dir 'actualizaciones.log'
$cfg  = Get-Content (Join-Path $dir 'config.json') -Raw | ConvertFrom-Json
$token = [Environment]::GetEnvironmentVariable('RUTASDE_TOKEN', 'User')
if (-not $token) { $token = $env:RUTASDE_TOKEN }
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# descarga un archivo del repositorio (con token, por la API de GitHub; sin token, por la dirección pública)
function Bajar($ruta, $destino, $segundos) {
    if ($token -and $cfg.api) {
        $h = @{ Authorization = "Bearer $token"; Accept = 'application/vnd.github.raw'; 'User-Agent' = 'RutaSDE' }
        $u = "$($cfg.api)/$ruta`?ref=main"
        if ($destino) { Invoke-WebRequest -UseBasicParsing -TimeoutSec $segundos -Headers $h $u -OutFile $destino }
        else { (Invoke-WebRequest -UseBasicParsing -TimeoutSec $segundos -Headers $h $u).Content }
    } else {
        $u = "$($cfg.base)/$ruta`?$([DateTime]::UtcNow.Ticks)"
        if ($destino) { Invoke-WebRequest -UseBasicParsing -TimeoutSec $segundos $u -OutFile $destino }
        else { (Invoke-WebRequest -UseBasicParsing -TimeoutSec $segundos $u).Content }
    }
}

try {
    $r = Bajar 'version.txt' $null 6
    if ($r -is [byte[]]) { $r = [Text.Encoding]::UTF8.GetString($r) }
    $remote = ([string]$r).Trim()
    $local  = if (Test-Path $verF) { (Get-Content $verF -Raw).Trim() } else { '' }
    if ($remote -match '^\d{8}-\d{4}$' -and $remote -ne $local) {
        $tmp = Join-Path $dir 'nueva.html'
        Bajar 'ruta-sde.html' $tmp 120
        $ok = (Test-Path $tmp) -and ((Get-Item $tmp).Length -gt 500000) -and (Select-String -Path $tmp -Pattern ('RSDE_VERSION="' + $remote + '"') -SimpleMatch -Quiet)
        if ($ok) {
            if (Test-Path $app) { Copy-Item $app (Join-Path $dir 'anterior.html') -Force }
            Move-Item $tmp $app -Force
            Set-Content $verF $remote
            Add-Content $log ("{0}  {1} -> {2}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm'), $local, $remote)
        } else {
            Remove-Item $tmp -Force
        }
    }
} catch { }

$url = ([Uri]$app).AbsoluteUri
$edge = @(
    "${env:ProgramFiles(x86)}\Microsoft\Edge\Application\msedge.exe",
    "$env:ProgramFiles\Microsoft\Edge\Application\msedge.exe",
    "$env:LOCALAPPDATA\Microsoft\Edge\Application\msedge.exe"
) | Where-Object { Test-Path $_ } | Select-Object -First 1
if ($edge) {
    Start-Process $edge -ArgumentList @("--app=$url", '--window-size=1320,900')
} else {
    Start-Process $app
}

# con la app ya abierta: copia a la computadora los videos que todavía no estén (la app los lee de la carpeta videos)
try {
    if ($token -and $cfg.api) {
        $h = @{ Authorization = "Bearer $token"; Accept = 'application/vnd.github+json'; 'User-Agent' = 'RutaSDE' }
        $lista = Invoke-RestMethod -TimeoutSec 15 -Headers $h "$($cfg.api)/videos?ref=main"
        $vdir = Join-Path $dir 'videos'
        New-Item -ItemType Directory -Force -Path $vdir | Out-Null
        foreach ($v in $lista) {
            if ($v.type -ne 'file' -or $v.name -notmatch '\.mp4$') { continue }
            $f = Join-Path $vdir $v.name
            if ((Test-Path $f) -and ((Get-Item $f).Length -eq $v.size)) { continue }
            $t = "$f.parcial"
            Bajar ("videos/" + $v.name) $t 600
            if ((Test-Path $t) -and ((Get-Item $t).Length -eq $v.size)) { Move-Item $t $f -Force } else { Remove-Item $t -Force }
        }
    }
} catch { }

# el lanzador también se mantiene al día: su propio código, el ícono y el nombre de los accesos directos
try {
    if ($token -and $cfg.api) {
        $nuevo = Join-Path $dir 'abrir.nuevo.ps1'
        Bajar 'lanzador/abrir.ps1' $nuevo 20
        if ((Test-Path $nuevo) -and (Select-String -Path $nuevo -Pattern '# rodMap-lanzador' -SimpleMatch -Quiet)) {
            $actual = Join-Path $dir 'abrir.ps1'
            if ((Get-FileHash $nuevo).Hash -ne (Get-FileHash $actual).Hash) { Move-Item $nuevo $actual -Force } else { Remove-Item $nuevo -Force }
        } else { Remove-Item $nuevo -Force }
        $icoN = Join-Path $dir 'icono.nuevo'
        Bajar 'lanzador/ruta-sde.ico' $icoN 20
        if ((Test-Path $icoN) -and ((Get-Item $icoN).Length -gt 1000)) {
            $nombre = 'rodmap-' + (Get-FileHash $icoN).Hash.Substring(0, 8).ToLower() + '.ico'
            if (-not (Test-Path (Join-Path $dir $nombre))) { Move-Item $icoN (Join-Path $dir $nombre) -Force } else { Remove-Item $icoN -Force }
        } else { Remove-Item $icoN -Force }
    }
    # el ícono vigente: el rodmap-*.ico más reciente (o el original, si todavía no hay ninguno)
    $icoActual = Get-ChildItem $dir -Filter 'rodmap-*.ico' | Sort-Object LastWriteTime -Descending | Select-Object -First 1
    $icoRuta = if ($icoActual) { $icoActual.FullName } else { Join-Path $dir 'ruta-sde.ico' }
    $ws = New-Object -ComObject WScript.Shell
    foreach ($l in @([Environment]::GetFolderPath('Desktop'), [Environment]::GetFolderPath('Programs'))) {
        $viejo = Join-Path $l 'Ruta SDE.lnk'; $bueno = Join-Path $l 'rodMap.lnk'
        if ((Test-Path $viejo) -and -not (Test-Path $bueno)) { Move-Item $viejo $bueno -Force }
        if (Test-Path $bueno) {
            $lnk = $ws.CreateShortcut($bueno)
            if ($lnk.IconLocation -ne "$icoRuta,0") {
                $lnk.IconLocation = "$icoRuta,0"
                $lnk.Description = 'rodMap: tu ruta de cero a trabajar en tecnología'
                $lnk.Save()
                $cambioIcono = $true
            }
        }
    }
    if ($cambioIcono) {
        # pide a Windows que vuelva a leer los íconos, y borra los íconos viejos que ya no usa ningún acceso directo
        Start-Process "$env:WINDIR\System32\ie4uinit.exe" -ArgumentList '-show' -WindowStyle Hidden
        Get-ChildItem $dir -Filter 'rodmap-*.ico' | Where-Object { $_.FullName -ne $icoRuta } | Remove-Item -Force
    }
} catch { }
