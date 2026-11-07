# EMYDPI v1.1.0 - Discord ve Roblox icin DPI/DNS atlatma
# https://github.com/yigitislamoglu/EMYDPI  (MIT)
# 1) hosts: secilen servislerin alan adlari -> 127.0.0.1
# 2) emydpi-proxy: 127.0.0.1:443'te dinler, gercek IP'yi DoH ile bulur,
#    TLS ClientHello'yu bolerek DPI'yi atlatir. Diger trafige dokunmaz.

param(
    [ValidateSet('install', 'uninstall', 'start', 'stop', 'status', 'log')]
    [string]$Action = 'status',
    [ValidateSet('tlsrec', 'frag')]
    [string]$Mode = 'tlsrec',
    # Virgulle ayrilmis: Discord,Roblox. Bos birakilirsa mevcut kurulum (yoksa hepsi) kullanilir.
    [string]$Services = ''
)

$ErrorActionPreference = 'Stop'
$Dir       = Split-Path -Parent $MyInvocation.MyCommand.Path
$ProxyPs1  = Join-Path $Dir 'emydpi-proxy.ps1'
$LogFile   = Join-Path $Dir 'emydpi.log'
$TaskName  = 'EMYDPI'
$HostsPath = Join-Path $env:SystemRoot 'System32\drivers\etc\hosts'
$Begin = '# >>> EMYDPI BASLANGIC (otomatik - elle duzenlemeyin)'
$End   = '# <<< EMYDPI BITIS'

$ServiceDomains = [ordered]@{
    Discord = @(
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
    # rbxcdn.com engelli degil, eklenmedi. Oyun sunuculari (UDP) IP ile baglanir, engelli degil.
    Roblox = @('roblox.com', 'ro.blox.com') + (@(
        'www', 'web', 'apis', 'apis.rcs', 'auth', 'users', 'accountsettings', 'accountinformation',
        'avatar', 'badges', 'catalog', 'chat', 'clientsettings', 'clientsettingscdn', 'contacts',
        'develop', 'economy', 'ecsv2', 'ephemeralcounters.api', 'friends', 'gamejoin', 'games',
        'groups', 'inventory', 'itemconfiguration', 'locale', 'notifications', 'premiumfeatures',
        'presence', 'privatemessages', 'realtime', 'realtime-signalr', 'thumbnails', 'trades',
        'translations', 'twostepverification', 'assetdelivery', 'assetgame', 'data', 'search',
        'followings', 'publish', 'metrics', 'lms', 'client-telemetry',
        'abtesting', 'adconfiguration', 'billing', 'setup', 'create', 'devforum', 'en.help',
        'voice', 'captcha', 'usermoderation', 'gamepersistence', 'share', 'talent', 'corp', 'blog'
    ) | ForEach-Object { "$_.roblox.com" })
}
$AllServices = @($ServiceDomains.Keys)

function Get-InstalledServices {
    $m = [regex]::Match((Read-Hosts), '# Servisler: ([A-Za-z, ]+)')
    if ($m.Success) { return @($m.Groups[1].Value -split '\s*,\s*' | Where-Object { $_ }) }
    if (Hosts-Active) { return @('Discord') }   # v1.0.0 kurulumu
    return @()
}

function Resolve-Services {
    if ($Services) {
        $list = @($Services -split '\s*,\s*' | Where-Object { $_ })
    } else {
        $list = Get-InstalledServices
        if ($list.Count -eq 0) { $list = $AllServices }
    }
    $bad = $list | Where-Object { $AllServices -notcontains $_ }
    if ($bad) { throw "Bilinmeyen servis: $($bad -join ', '). Gecerli: $($AllServices -join ', ')" }
    # sirayi koru
    return @($AllServices | Where-Object { $list -contains $_ })
}

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
        -Settings $settings -Description 'EMYDPI - Discord/Roblox DPI atlatma proxy' -Force | Out-Null
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

function Restart-Apps([string[]]$svc) {
    if ($svc -contains 'Discord') {
        Write-Host '[+] Discord yeniden baslatiliyor...' -ForegroundColor Green
        Stop-Discord; Start-Sleep 1; Start-Discord
    }
    if ($svc -contains 'Roblox') {
        $rb = @(Get-Process -Name 'RobloxPlayerBeta', 'RobloxStudioBeta' -ErrorAction SilentlyContinue)
        if ($rb.Count -gt 0) { Write-Host '[i] Roblox acik: degisikligin gecerli olmasi icin Roblox''u kapatip yeniden acin.' -ForegroundColor Yellow }
        else { Write-Host '[+] Roblox hazir: Roblox''u veya roblox.com''u acabilirsiniz.' -ForegroundColor Green }
    }
}

# ---------------- islemler ----------------
switch ($Action) {
    'install' {
        $svc = Resolve-Services
        $domains = @($svc | ForEach-Object { $ServiceDomains[$_] })
        $lines = @($domains | ForEach-Object { "127.0.0.1`t$_" })
        $cur = Read-Hosts
        $m = [regex]::Match($cur, '(?s)' + [regex]::Escape($Begin) + '(.*?)' + [regex]::Escape($End))
        $curLines = @()
        if ($m.Success) { $curLines = @($m.Groups[1].Value -split "`r?`n" | Where-Object { $_ -like '127.0.0.1*' }) }
        $alreadyOk = $m.Success -and ((Get-InstalledServices) -join ',') -eq ($svc -join ',') -and
                     (($curLines -join "`n") -eq ($lines -join "`n"))
        if ($alreadyOk) {
            Write-Host '[+] hosts zaten dogru, dokunulmadi (antivirus duraklatmaya gerek yok).' -ForegroundColor Green
        } else {
            $block = @($Begin,
                       ('# Servisler: ' + ($svc -join ',')),
                       ('# Kurulum: ' + (Get-Date -Format 'yyyy-MM-dd HH:mm'))) + $lines + @($End)
            $text  = (Remove-Block $cur).TrimEnd() + "`r`n`r`n" + ($block -join "`r`n") + "`r`n"
            Write-Hosts $text
            Write-Host ("[+] hosts: {0} ({1} alan adi) 127.0.0.1'e yonlendirildi." -f ($svc -join ' + '), $domains.Count) -ForegroundColor Green
        }
        Register-Task
        if (Start-Proxy) {
            ipconfig /flushdns | Out-Null
            Write-Host '[+] DNS onbellegi temizlendi.' -ForegroundColor Green
            Restart-Apps $svc
        }
    }

    'uninstall' {
        Stop-Proxy
        Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false -ErrorAction SilentlyContinue
        if (Hosts-Active) { Write-Hosts (Remove-Block (Read-Hosts)) }
        ipconfig /flushdns | Out-Null
        Write-Host '[+] EMYDPI tamamen kaldirildi (proxy, otomatik baslatma, hosts kayitlari).' -ForegroundColor Green
    }

    'start' { if (Start-Proxy) { Restart-Apps (Get-InstalledServices) } }

    'stop' {
        Stop-Proxy
        Write-Host '[+] Proxy durduruldu.' -ForegroundColor Yellow
        if (Hosts-Active) { Write-Host '    Not: hosts kayitlari duruyor; proxy kapaliyken Discord/Roblox baglanamaz.' -ForegroundColor Yellow }
    }

    'status' {
        $h = Hosts-Active
        $p = Proxy-Running
        $t = [bool](Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue)
        $s = Get-InstalledServices
        function S($ok) { if ($ok) { 'ACIK ' } else { 'KAPALI' } }
        Write-Host ('  servisler         : {0}' -f $(if ($s.Count) { $s -join ' + ' } else { '-' })) -ForegroundColor $(if ($s.Count) { 'Green' } else { 'Yellow' })
        Write-Host ('  hosts yonlendirme : {0}' -f (S $h)) -ForegroundColor $(if ($h) { 'Green' } else { 'Yellow' })
        Write-Host ('  proxy             : {0}' -f (S $p)) -ForegroundColor $(if ($p) { 'Green' } else { 'Yellow' })
        Write-Host ('  otomatik baslatma : {0}' -f (S $t)) -ForegroundColor $(if ($t) { 'Green' } else { 'Yellow' })
        if ($h -and -not $p) { Write-Host '  [!] hosts aktif ama proxy kapali: baglanti olmaz. [3] ile baslatin.' -ForegroundColor Red }
    }

    'log' {
        if (Test-Path $LogFile) { Get-Content $LogFile -Tail 40 } else { Write-Host 'Log yok.' }
    }
}
