# EMYDPI - Discord'a ozel DPI/DNS atlatma
# 1) hosts: Discord alan adlari -> 127.0.0.1
# 2) emydpi-proxy: 127.0.0.1:443'te dinler, gercek IP'yi DoH ile bulur,
#    TLS ClientHello'yu bolerek DPI'yi atlatir. Diger trafige dokunmaz.

param(
    [ValidateSet('install', 'uninstall', 'start', 'stop', 'status', 'log')]
    [string]$Action = 'status',
    [ValidateSet('tlsrec', 'frag')]
    [string]$Mode = 'tlsrec'
)

$ErrorActionPreference = 'Stop'
$Dir       = Split-Path -Parent $MyInvocation.MyCommand.Path
$ProxyPs1  = Join-Path $Dir 'emydpi-proxy.ps1'
$LogFile   = Join-Path $Dir 'emydpi.log'
$TaskName  = 'EMYDPI'
$HostsPath = Join-Path $env:SystemRoot 'System32\drivers\etc\hosts'
$Begin = '# >>> EMYDPI BASLANGIC (otomatik - elle duzenlemeyin)'
$End   = '# <<< EMYDPI BITIS'

$Domains = @(
    'discord.com', 'www.discord.com', 'canary.discord.com', 'ptb.discord.com',
    'status.discord.com', 'support.discord.com', 'updates.discord.com', 'click.discord.com',
    'discord.gg', 'gateway.discord.gg', 'remote-auth-gateway.discord.gg',
    'discord.media', 'latency.discord.media',
    'discord.co', 'discord.new', 'discord.gift', 'discord.dev',
    'discordapp.com', 'www.discordapp.com', 'cdn.discordapp.com',
    'dl.discordapp.net', 'media.discordapp.net',
    'images-ext-1.discordapp.net', 'images-ext-2.discordapp.net',
    'discordcdn.com', 'discord-attachments-uploads-prd.storage.googleapis.com'
)

# ---------------- hosts ----------------
function Read-Hosts { if (Test-Path $HostsPath) { [IO.File]::ReadAllText($HostsPath) } else { '' } }

function Remove-Block([string]$text) {
    $pattern = '(?s)\r?\n?' + [regex]::Escape($Begin) + '.*?' + [regex]::Escape($End) + '\r?\n?'
    return [regex]::Replace($text, $pattern, "`r`n").TrimEnd() + "`r`n"
}

function Write-Hosts([string]$text) {
    $backup = "$HostsPath.emydpi.bak"
    if (-not (Test-Path $backup)) { Copy-Item $HostsPath $backup -Force }
    try { (Get-Item $HostsPath).IsReadOnly = $false } catch { }
    try {
        [IO.File]::WriteAllText($HostsPath, $text, [Text.Encoding]::ASCII)
    } catch [UnauthorizedAccessException] {
        Write-Host ''
        Write-Host '[!] hosts dosyasina yazma ENGELLENDI.' -ForegroundColor Red
        $av = @()
        try { $av = @(Get-CimInstance -Namespace root/SecurityCenter2 -ClassName AntiVirusProduct |
                      Where-Object { $_.displayName -ne 'Windows Defender' } | ForEach-Object { $_.displayName }) } catch { }
        if ($av.Count -gt 0) { Write-Host ("    Antivirus hosts dosyasini koruyor: {0}" -f ($av -join ', ')) -ForegroundColor Yellow }
        Write-Host '    Cozum: antivirus korumasini birkac dakikaligina duraklatin, tekrar deneyin,' -ForegroundColor Yellow
        Write-Host '    sonra korumayi geri acin. (Sadece kurulum/kaldirmada gerekir.)' -ForegroundColor Yellow
        exit 2
    }
}

function Hosts-Active { (Read-Hosts) -match [regex]::Escape($Begin) }

# ---------------- proxy ----------------
function Get-ProxyProcs {
    @(Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" |
      Where-Object { $_.CommandLine -like '*emydpi-proxy.ps1*' })
}

function Proxy-Running { @(Get-ProxyProcs).Count -gt 0 }

function Stop-Proxy {
    try { Stop-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue } catch { }
    Get-ProxyProcs | ForEach-Object { try { Stop-Process -Id $_.ProcessId -Force } catch { } }
}

function Start-Proxy {
    Stop-Proxy
    if (Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue) {
        Start-ScheduledTask -TaskName $TaskName
    } else {
        Start-Process conhost.exe -WindowStyle Hidden -ArgumentList (Get-ProxyArgs)
    }
    for ($i = 0; $i -lt 20; $i++) {
        Start-Sleep -Milliseconds 500
        if (Get-NetTCPConnection -LocalAddress 127.0.0.1 -LocalPort 443 -State Listen -ErrorAction SilentlyContinue) {
            Write-Host '[+] Proxy calisiyor (127.0.0.1:443).' -ForegroundColor Green
            return $true
        }
    }
    Write-Host '[!] Proxy baslamadi. Ayrintilar icin menude "Log" secenegine bakin.' -ForegroundColor Red
    $busy = Get-NetTCPConnection -LocalPort 443 -State Listen -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($busy) {
        $pn = (Get-Process -Id $busy.OwningProcess -ErrorAction SilentlyContinue).ProcessName
        Write-Host "    443 portunu baska bir program kullaniyor: $pn (PID $($busy.OwningProcess))" -ForegroundColor Yellow
    }
    return $false
}

# conhost --headless: Windows Terminal varsayilan olsa bile hic pencere acilmaz
function Get-ProxyArgs {
    "--headless powershell.exe -NoProfile -ExecutionPolicy Bypass -File `"$ProxyPs1`" -Mode $Mode"
}

function Register-Task {
    $action    = New-ScheduledTaskAction -Execute 'conhost.exe' -Argument (Get-ProxyArgs) -WorkingDirectory $Dir
    $user      = "$env:USERDOMAIN\$env:USERNAME"
    $trigger   = New-ScheduledTaskTrigger -AtLogOn -User $user
    $principal = New-ScheduledTaskPrincipal -UserId $user -LogonType Interactive -RunLevel Limited
    $settings  = New-ScheduledTaskSettingsSet -ExecutionTimeLimit ([TimeSpan]::Zero) -AllowStartIfOnBatteries `
                   -DontStopIfGoingOnBatteries -RestartCount 3 -RestartInterval (New-TimeSpan -Minutes 1) -MultipleInstances IgnoreNew
    Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger $trigger -Principal $principal `
        -Settings $settings -Description 'EMYDPI - Discord DPI atlatma proxy' -Force | Out-Null
    Write-Host '[+] Oturum acilisinda otomatik baslatma ayarlandi.' -ForegroundColor Green
}

function Stop-Discord {
    Get-Process -Name 'Discord', 'DiscordCanary', 'DiscordPTB', 'Update' -ErrorAction SilentlyContinue |
        Where-Object { $_.Path -like "*Discord*" } | ForEach-Object { try { Stop-Process -Id $_.Id -Force } catch { } }
}

function Start-Discord {
    # explorer uzerinden actiriyoruz ki Discord yonetici olarak degil, normal kullanici olarak calissin
    $lnk = Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs\Discord Inc\Discord.lnk'
    if (Test-Path $lnk) { Start-Process explorer.exe -ArgumentList "`"$lnk`"" }
    else { Write-Host '    Discord kisayolu bulunamadi, Discord''u kendiniz acin.' -ForegroundColor Yellow }
}

# ---------------- islemler ----------------
switch ($Action) {
    'install' {
        $lines = $Domains | ForEach-Object { "127.0.0.1`t$_" }
        $cur = Read-Hosts
        $alreadyOk = (Hosts-Active) -and -not ($lines | Where-Object { $cur -notmatch [regex]::Escape($_) })
        if ($alreadyOk) {
            Write-Host '[+] hosts zaten dogru, dokunulmadi (antivirus duraklatmaya gerek yok).' -ForegroundColor Green
        } else {
            $block = @($Begin, ('# Kurulum: ' + (Get-Date -Format 'yyyy-MM-dd HH:mm'))) + $lines + @($End)
            $text  = (Remove-Block $cur).TrimEnd() + "`r`n`r`n" + ($block -join "`r`n") + "`r`n"
            Write-Hosts $text
            Write-Host "[+] hosts: $($Domains.Count) Discord alan adi 127.0.0.1'e yonlendirildi." -ForegroundColor Green
        }
        Register-Task
        if (Start-Proxy) {
            ipconfig /flushdns | Out-Null
            Write-Host '[+] DNS onbellegi temizlendi. Discord yeniden baslatiliyor...' -ForegroundColor Green
            Stop-Discord; Start-Sleep 1; Start-Discord
        }
    }

    'uninstall' {
        Stop-Proxy
        Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false -ErrorAction SilentlyContinue
        if (Hosts-Active) { Write-Hosts (Remove-Block (Read-Hosts)) }
        ipconfig /flushdns | Out-Null
        Write-Host '[+] EMYDPI tamamen kaldirildi (proxy, otomatik baslatma, hosts kayitlari).' -ForegroundColor Green
    }

    'start' { if (Start-Proxy) { Stop-Discord; Start-Sleep 1; Start-Discord } }

    'stop' {
        Stop-Proxy
        Write-Host '[+] Proxy durduruldu.' -ForegroundColor Yellow
        if (Hosts-Active) { Write-Host '    Not: hosts kayitlari duruyor; proxy kapaliyken Discord baglanamaz.' -ForegroundColor Yellow }
    }

    'status' {
        $h = Hosts-Active
        $p = Proxy-Running
        $t = [bool](Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue)
        function S($ok) { if ($ok) { 'ACIK ' } else { 'KAPALI' } }
        Write-Host ('  hosts yonlendirme : {0}' -f (S $h)) -ForegroundColor $(if ($h) { 'Green' } else { 'Yellow' })
        Write-Host ('  proxy             : {0}' -f (S $p)) -ForegroundColor $(if ($p) { 'Green' } else { 'Yellow' })
        Write-Host ('  otomatik baslatma : {0}' -f (S $t)) -ForegroundColor $(if ($t) { 'Green' } else { 'Yellow' })
        if ($h -and -not $p) { Write-Host '  [!] hosts aktif ama proxy kapali: Discord baglanamaz. [3] ile baslatin.' -ForegroundColor Red }
    }

    'log' {
        if (Test-Path $LogFile) { Get-Content $LogFile -Tail 40 } else { Write-Host 'Log yok.' }
    }
}
