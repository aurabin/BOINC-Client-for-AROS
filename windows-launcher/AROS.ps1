param(
    [switch]$SetupOnly,
    [switch]$Update,
    [switch]$ShareWindowsFiles,
    [switch]$WritableShare
)

$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot
if ($env:AROS_SETUP_DIRECTORY) { $root = $env:AROS_SETUP_DIRECTORY }
$data = Join-Path $root 'AROS-Daten'
$baseUrl = 'https://www.axrt.org/download/aros/v11/'
$baseline = '202609'
$releasePattern = '[0-9]{6}(?:[0-9]{2})?(?:-[0-9]+)?'

function Get-ReleaseOrder([string[]]$Releases) {
    $Releases | Sort-Object -Unique -Descending -Property @(
        { ($_.Split('-')[0]).PadRight(8, '0') },
        { if ($_.Contains('-')) { [long]$_.Split('-')[1] } else { 0 } }
    )
}

function Find-Qemu {
    $command = Get-Command qemu-system-x86_64.exe -ErrorAction SilentlyContinue
    if ($command) { return $command.Source }
    foreach ($folder in @($env:ProgramFiles, $env:LOCALAPPDATA, $root)) {
        if ($folder) {
            $candidate = Join-Path $folder 'qemu\qemu-system-x86_64.exe'
            if (Test-Path -LiteralPath $candidate -PathType Leaf) { return $candidate }
        }
    }
}

function Save-ArosImage([string]$Release, [string]$Destination) {
    $stage = Join-Path $data ([guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $stage | Out-Null
    $archivePath = Join-Path $stage 'aros.zip'
    $imagePath = Join-Path $stage 'aros.iso'
    try {
        Write-Host "Lade AROS $Release x86-64 herunter ..."
        $url = $baseUrl + "AROS-$Release-pc-x86_64-boot-iso.zip"
        Invoke-WebRequest -UseBasicParsing -Uri $url -OutFile $archivePath -TimeoutSec 600
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        $archive = [IO.Compression.ZipFile]::OpenRead($archivePath)
        try {
            $images = @($archive.Entries | Where-Object { $_.Name -like '*.iso' })
            if ($images.Count -ne 1) { throw 'Das Archiv muss genau ein ISO enthalten.' }
            [IO.Compression.ZipFileExtensions]::ExtractToFile($images[0], $imagePath)
        } finally {
            $archive.Dispose()
        }

        $image = [IO.File]::OpenRead($imagePath)
        try {
            $image.Position = 32769
            $signature = New-Object byte[] 5
            if ($image.Read($signature, 0, 5) -ne 5 -or
                [Text.Encoding]::ASCII.GetString($signature) -ne 'CD001') {
                throw 'Das heruntergeladene ISO hat keinen ISO-9660-Header.'
            }
        } finally {
            $image.Dispose()
        }
        [IO.File]::Move($imagePath, $Destination)
    } finally {
        Remove-Item -LiteralPath $archivePath, $imagePath, $stage -ErrorAction SilentlyContinue
    }
}

function Assert-ShareHasNoLinks([IO.DirectoryInfo]$Folder) {
    if ($Folder.Attributes -band [IO.FileAttributes]::ReparsePoint) {
        throw "Der Austauschordner darf keine Verknuepfung sein: $Folder"
    }
    foreach ($item in Get-ChildItem -LiteralPath $Folder.FullName -Force) {
        if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) {
            throw "Verknuepfungen sind im Austauschordner nicht erlaubt: $($item.FullName)"
        }
        if ($item.PSIsContainer) { Assert-ShareHasNoLinks $item }
    }
}

if ($WritableShare -and !$ShareWindowsFiles) {
    throw '-WritableShare benoetigt -ShareWindowsFiles.'
}

New-Item -ItemType Directory -Path $data -Force | Out-Null
$lockPath = Join-Path $data 'launcher.lock'
try {
    $lock = [IO.File]::Open($lockPath, 'OpenOrCreate', 'ReadWrite', 'None')
} catch [IO.IOException] {
    throw "AROS wird bereits ausgefuehrt oder der Ordner ist gesperrt: $data"
}

try {
    $cached = @(
        Get-ChildItem -LiteralPath $data -File -Filter 'AROS-*.iso' |
            ForEach-Object {
                if ($_.Length -gt 32774 -and $_.Name -match "^AROS-($releasePattern)\.iso$") {
                    $Matches[1]
                }
            }
    )
    $legacy = Join-Path $data 'AROS-x86-64.iso'
    if ((Test-Path -LiteralPath $legacy -PathType Leaf) -and
        (Get-Item -LiteralPath $legacy).Length -gt 32774) {
        $cached += $baseline
    }
    $installed = @((Get-ReleaseOrder $cached))[0]
    $target = $installed
    if ($Update -or !$installed) {
        try {
            $index = Invoke-WebRequest -UseBasicParsing -Uri $baseUrl -TimeoutSec 30
            $available = @([regex]::Matches(
                $index.Content, 'href="AROS-(' + $releasePattern + ')-pc-x86_64-boot-iso\.zip"'
            ) | ForEach-Object { $_.Groups[1].Value })
            if (!$available.Count) { throw 'Keine passenden AROS-ISO-Archive gefunden.' }
            $target = @(Get-ReleaseOrder ($available + @($cached) + $baseline))[0]
        } catch {
            if ($Update) { throw }
            Write-Warning 'Versionsliste nicht erreichbar. Verwende die mitgelieferte Download-Adresse.'
            $target = $baseline
        }
    }

    $iso = Join-Path $data "AROS-$target.iso"
    if ($target -eq $baseline -and $cached -contains $baseline -and !(Test-Path -LiteralPath $iso)) {
        $iso = $legacy
    }
    if ($cached -notcontains $target) {
        Save-ArosImage $target $iso
    }
    if ($Update) {
        Write-Host "AROS $target ist lokal verfuegbar."
        return
    }

    $qemu = Find-Qemu
    if (!$qemu) {
        Write-Host 'QEMU fehlt. Windows Paket-Manager startet die Installation.'
        if (!(Get-Command winget.exe -ErrorAction SilentlyContinue)) {
            throw 'WinGet fehlt. Installiere QEMU von https://www.qemu.org/download/ und starte erneut.'
        }
        & winget.exe install --exact --id SoftwareFreedomConservancy.QEMU --source winget
        $qemu = Find-Qemu
        if (!$qemu) { throw 'QEMU wurde nicht gefunden. Schliesse dieses Fenster und starte erneut.' }
    }
    if ($SetupOnly) { return }

    $qemuArgs = @('-m', '1024', '-boot', 'd', '-cdrom', $iso, '-nic', 'none')
    if ($ShareWindowsFiles) {
        $share = Join-Path $root 'AROS-Austausch'
        New-Item -ItemType Directory -Force -Path $share | Out-Null
        Assert-ShareHasNoLinks (Get-Item -LiteralPath $share -Force)
        $sharePath = $share.Replace(',', ',,')
        $mode = 'off'
        if ($WritableShare) { $mode = 'on' }
        $drive = "if=none,id=winshare,format=raw,file.driver=vvfat,file.dir=$sharePath,file.label=WINDOWS,file.rw=$mode"
        if (!$WritableShare) { $drive += ',readonly=on' }
        $qemuArgs += @('-usb', '-drive', $drive, '-device', 'usb-storage,drive=winshare')
        Write-Host "Windows-Austauschordner: $share"
    }
    & $qemu @qemuArgs
    if ($LASTEXITCODE -ne 0) { throw "QEMU endete mit Fehlercode $LASTEXITCODE." }
} finally {
    $lock.Dispose()
}

