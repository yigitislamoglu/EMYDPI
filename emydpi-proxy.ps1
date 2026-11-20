# EMYDPI proxy baslatici - emydpi-proxy.cs dosyasini derleyip calistirir
param(
    [int]$Port = 443,
    [ValidateSet('auto', 'oob', 'oob2', 'tlsrec', 'recfrag', 'multi', 'frag')]
    [string]$Mode = 'auto'
)
$ErrorActionPreference = 'Stop'
$dir = Split-Path -Parent $MyInvocation.MyCommand.Path
$host.UI.RawUI.WindowTitle = 'EMYDPI proxy'
Add-Type -Path (Join-Path $dir 'emydpi-proxy.cs')
# Port gecici olarak mesgulse (or. uykudan donus) birkac kez tekrar dene
for ($i = 0; $i -lt 20; $i++) {
    try { [EmyProxy]::Run($Port, $Mode, (Join-Path $dir 'emydpi.log')) } catch { Start-Sleep -Seconds 3 }
}
exit 1
