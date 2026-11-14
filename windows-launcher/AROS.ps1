param(
    [switch]$SetupOnly,
    [switch]$Update,
    [switch]$ShareWindowsFiles,
    [switch]$WritableShare,
    [switch]$WindowsDesktop,
    [ValidateRange(1, 65535)][int]$DesktopPort = 5900,
    [switch]$OfflineIso,
    [string]$IsoPath,
    [switch]$ChatGPT
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

function Assert-IsoImage([string]$Path) {
    $image = [IO.File]::OpenRead($Path)
    try {
        $image.Position = 32769
        $signature = New-Object byte[] 5
        if ($image.Read($signature, 0, 5) -ne 5 -or
            [Text.Encoding]::ASCII.GetString($signature) -ne 'CD001') {
            throw "Die Datei hat keinen ISO-9660-Header: $Path"
        }
    } finally {
        $image.Dispose()
    }
}

function Select-OfflineIso {
    Add-Type -AssemblyName System.Windows.Forms
    $dialog = New-Object Windows.Forms.OpenFileDialog
    try {
        $dialog.Title = 'AROS Wizard powered by ChatGPT - Offline-ISO auswaehlen'
        $dialog.Filter = 'ISO-Dateien (*.iso)|*.iso'
        $dialog.CheckFileExists = $true
        if ($dialog.ShowDialog() -eq [Windows.Forms.DialogResult]::OK) { $dialog.FileName }
    } finally {
        $dialog.Dispose()
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

        Assert-IsoImage $imagePath
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

$chatBridge = {
    param([string]$ReadyPath)
    $ErrorActionPreference = 'Stop'
    $encoding = [Text.Encoding]::GetEncoding(28591)
    $model = $env:OPENAI_MODEL
    if (!$model) { $model = 'gpt-4.1-mini' }
    $headers = @{ Authorization = 'Bearer ' + $env:OPENAI_API_KEY }
    $listener = [Net.Sockets.TcpListener]::new([Net.IPAddress]::Loopback, 0)
    $client = $null
    try {
        $listener.Start()
        [IO.File]::WriteAllText($ReadyPath, [string]$listener.LocalEndpoint.Port)
        $client = $listener.AcceptTcpClient()
        $listener.Stop()
        $stream = $client.GetStream()
        $reader = [IO.StreamReader]::new($stream, $encoding, $false)
        $history = @()
        while ($true) {
            $line = [Text.StringBuilder]::new()
            while (($value = $reader.Read()) -ne -1 -and $value -ne 10) {
                if ($line.Length -ge 4000) { return }
                [void]$line.Append([char]$value)
            }
            if ($value -eq -1) { return }
            $prompt = $line.ToString().Trim()
            if (!$prompt) { continue }
            if ($prompt -eq '/reset') {
                $history = @()
                $answer = 'Neue Unterhaltung.'
            } else {
                $inputMessages = @($history) + @{ role = 'user'; content = $prompt }
                $body = @{
                    model = $model
                    input = $inputMessages
                    max_output_tokens = 700
                    store = $false
                } | ConvertTo-Json -Depth 6 -Compress
                try {
                    $response = Invoke-RestMethod -Method Post -Uri 'https://api.openai.com/v1/responses' `
                        -Headers $headers -ContentType 'application/json; charset=utf-8' `
                        -Body ([Text.Encoding]::UTF8.GetBytes($body)) -TimeoutSec 60
                    $answer = @(
                        foreach ($item in $response.output) {
                            if ($item.type -ne 'message') { continue }
                            foreach ($part in $item.content) {
                                if ($part.type -eq 'output_text') { $part.text }
                                if ($part.type -eq 'refusal') { $part.refusal }
                            }
                        }
                    ) -join "`n"
                    if (!$answer) { $answer = 'OpenAI hat keine Textantwort geliefert.' }
                    $history = @($inputMessages + @{ role = 'assistant'; content = $answer } |
                        Select-Object -Last 8)
                } catch {
                    $status = $_.Exception.Response
                    $answer = 'OpenAI-Anfrage fehlgeschlagen. Pruefe die Windows-Internetverbindung.'
                    if ($status) {
                        $answer = 'OpenAI-Anfrage fehlgeschlagen (HTTP ' + [int]$status.StatusCode + ').'
                    }
                }
            }
            $answer = $answer -replace '[\x00-\x08\x0B\x0C\x0E-\x1F\x7F-\x9F]', ''
            $bytes = $encoding.GetBytes($answer)
            $size = [Text.Encoding]::ASCII.GetBytes([string]$bytes.Length + "`n")
            $stream.Write($size, 0, $size.Length)
            $stream.Write($bytes, 0, $bytes.Length)
        }
    } finally {
        if ($client) { $client.Dispose() }
        $listener.Stop()
    }
}

if ($ChatGPT -and ($Update -or $SetupOnly)) {
    throw '-ChatGPT benoetigt einen normalen VM-Start.'
}
if ($ChatGPT -and [string]::IsNullOrWhiteSpace($env:OPENAI_API_KEY)) {
    throw 'Setze OPENAI_API_KEY unter Windows, bevor du den Chat startest.'
}

if ($WritableShare -and !$ShareWindowsFiles) {
    throw '-WritableShare benoetigt -ShareWindowsFiles.'
}

$useOfflineIso = $OfflineIso -or $PSBoundParameters.ContainsKey('IsoPath')
if ($useOfflineIso -and $Update) {
    throw 'Eine lokale ISO kann nicht gleichzeitig mit -Update gestartet werden.'
}
if ($useOfflineIso) {
    if (!$PSBoundParameters.ContainsKey('IsoPath')) {
        $IsoPath = Select-OfflineIso
        if (!$IsoPath) { return }
    }
    if ([string]::IsNullOrWhiteSpace($IsoPath)) { throw 'Bitte einen ISO-Pfad angeben.' }
    $file = Get-Item -LiteralPath $IsoPath
    if ($file -isnot [IO.FileInfo] -or $file.Extension -ne '.iso') {
        throw "Bitte eine ISO-Datei auswaehlen: $IsoPath"
    }
    $iso = $file.FullName
    Assert-IsoImage $iso
}

if ($WindowsDesktop -and ($Update -or $SetupOnly)) {
    throw '-WindowsDesktop benoetigt einen normalen VM-Start.'
}

if ($WindowsDesktop) {
    try {
        $listeners = @([Net.NetworkInformation.IPGlobalProperties]::GetIPGlobalProperties().
            GetActiveTcpListeners() | Where-Object { $_.Port -eq $DesktopPort })
    } catch [Management.Automation.MethodInvocationException] {
        $listeners = $null
        Write-Warning "VNC-Listener nicht pruefbar. Der Server muss nur auf 127.0.0.1:$DesktopPort lauschen."
    }
    if ($null -ne $listeners) {
        $loopback = @($listeners | Where-Object { $_.Address.Equals([Net.IPAddress]::Loopback) })
        $external = @($listeners | Where-Object { ![Net.IPAddress]::IsLoopback($_.Address) })
        if (!$loopback.Count -or $external.Count) {
            throw "Starte den Windows-VNC-Server nur auf 127.0.0.1:$DesktopPort."
        }
    }
}

New-Item -ItemType Directory -Path $data -Force | Out-Null
$lockPath = Join-Path $data 'launcher.lock'
try {
    $lock = [IO.File]::Open($lockPath, 'OpenOrCreate', 'ReadWrite', 'None')
} catch [IO.IOException] {
    throw "AROS wird bereits ausgefuehrt oder der Ordner ist gesperrt: $data"
}

try {
    if (!$useOfflineIso) {
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
    }

    $qemu = Find-Qemu
    if (!$qemu) {
        if ($useOfflineIso) { throw 'Fuer den Offline-Start muss QEMU bereits installiert sein.' }
        Write-Host 'QEMU fehlt. Windows Paket-Manager startet die Installation.'
        if (!(Get-Command winget.exe -ErrorAction SilentlyContinue)) {
            throw 'WinGet fehlt. Installiere QEMU von https://www.qemu.org/download/ und starte erneut.'
        }
        & winget.exe install --exact --id SoftwareFreedomConservancy.QEMU --source winget
        $qemu = Find-Qemu
        if (!$qemu) { throw 'QEMU wurde nicht gefunden. Schliesse dieses Fenster und starte erneut.' }
    }
    if ($SetupOnly) { return }

    $forwarding = @()
    if ($WindowsDesktop) {
        $forwarding += "guestfwd=tcp:10.0.2.100:5900-tcp:127.0.0.1:$DesktopPort"
        Write-Host 'Windows-Desktop: VNC-Client in AROS mit 10.0.2.100:5900 verbinden.'
    }
    if ($ChatGPT) {
        $chatReady = Join-Path $data ([guid]::NewGuid().ToString('N') + '.chat-port')
        $chatJob = Start-Job -ScriptBlock $chatBridge -ArgumentList $chatReady
        $deadline = [DateTime]::UtcNow.AddSeconds(15)
        do {
            Start-Sleep -Milliseconds 150
            $chatPort = Get-Content -LiteralPath $chatReady -ErrorAction SilentlyContinue
        } until ($chatPort -match '^[0-9]+$' -or $chatJob.State -in 'Completed', 'Failed', 'Stopped' -or
            [DateTime]::UtcNow -ge $deadline)
        if ($chatPort -notmatch '^[0-9]+$') { throw 'ChatGPT-Verbindung konnte nicht gestartet werden.' }
        $forwarding += "guestfwd=tcp:10.0.2.100:16811-tcp:127.0.0.1:$chatPort"
        Write-Host 'ChatGPT for AROS: Netzwerk in AROS starten und ChatGPT in AROS ausfuehren.'
    }
    $network = 'none'
    if ($forwarding.Count) {
        $network = 'user,model=rtl8139,restrict=on,' + ($forwarding -join ',')
    }
    $qemuArgs = @('-m', '1024', '-boot', 'd', '-cdrom', $iso, '-nic', $network)
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
    $savedApiKey = $env:OPENAI_API_KEY
    try {
        Remove-Item Env:OPENAI_API_KEY -ErrorAction SilentlyContinue
        & $qemu @qemuArgs
    } finally {
        if ($null -ne $savedApiKey) { $env:OPENAI_API_KEY = $savedApiKey }
    }
    if ($LASTEXITCODE -ne 0) { throw "QEMU endete mit Fehlercode $LASTEXITCODE." }
} finally {
    if ($chatJob) { Remove-Job -Job $chatJob -Force }
    if ($chatReady) { Remove-Item -LiteralPath $chatReady -ErrorAction SilentlyContinue }
    $lock.Dispose()
}

