# EMYDPI proxy baslatici - emydpi-proxy.cs dosyasini derleyip calistirir
param(
    [int]$Port = 443,
    [ValidateSet('auto', 'tlsrec', 'multi', 'recfrag', 'frag')]
    [string]$Mode = 'auto'
)
$ErrorActionPreference = 'Stop'
$dir = Split-Path -Parent $MyInvocation.MyCommand.Path
$host.UI.RawUI.WindowTitle = 'EMYDPI proxy'
Add-Type -Path (Join-Path $dir 'emydpi-proxy.cs')
[EmyProxy]::Run($Port, $Mode, (Join-Path $dir 'emydpi.log'))
