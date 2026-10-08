# Turns adult-site blocking on or off for this PC. Needs admin (Focus Board asks via UAC).
#  On : every connected network adapter uses Cloudflare for Families (blocks adult + malware sites),
#       and browsers are stopped from using their own "secure DNS", which would skip the filter.
#  Off: adapters go back to automatic DNS and the browser policies are removed.
param([Parameter(Mandatory)][ValidateSet('On', 'Off')][string]$Mode)
$ErrorActionPreference = 'Stop'

$familyDns = @('1.1.1.3', '1.0.0.3', '2606:4700:4700::1113', '2606:4700:4700::1003')

# Browser policies that disable built-in DNS-over-HTTPS
$chromiumPolicies = @(
    'HKLM:\SOFTWARE\Policies\Google\Chrome',
    'HKLM:\SOFTWARE\Policies\Microsoft\Edge',
    'HKLM:\SOFTWARE\Policies\BraveSoftware\Brave'
)
$firefoxPolicy = 'HKLM:\SOFTWARE\Policies\Mozilla\Firefox\DNSOverHTTPS'

try {
    $adapters = Get-NetAdapter | Where-Object { $_.Status -eq 'Up' }
    foreach ($a in $adapters) {
        if ($Mode -eq 'On') {
            Set-DnsClientServerAddress -InterfaceIndex $a.ifIndex -ServerAddresses $familyDns
        } else {
            Set-DnsClientServerAddress -InterfaceIndex $a.ifIndex -ResetServerAddresses
        }
    }

    foreach ($key in $chromiumPolicies) {
        if ($Mode -eq 'On') {
            New-Item -Path $key -Force | Out-Null
            Set-ItemProperty -Path $key -Name DnsOverHttpsMode -Value 'off'
        } elseif (Test-Path $key) {
            Remove-ItemProperty -Path $key -Name DnsOverHttpsMode -ErrorAction SilentlyContinue
        }
    }
    if ($Mode -eq 'On') {
        New-Item -Path $firefoxPolicy -Force | Out-Null
        Set-ItemProperty -Path $firefoxPolicy -Name Enabled -Value 0 -Type DWord
        Set-ItemProperty -Path $firefoxPolicy -Name Locked -Value 1 -Type DWord
    } elseif (Test-Path $firefoxPolicy) {
        Remove-Item -Path $firefoxPolicy -Recurse -Force
    }

    Clear-DnsClientCache
    exit 0
} catch {
    Add-Type -AssemblyName System.Windows.Forms
    [System.Windows.Forms.MessageBox]::Show("Could not change DNS settings:`n$($_.Exception.Message)", 'Focus Board') | Out-Null
    exit 1
}
