function Start-RDPLauncher {
    <#
    .SYNOPSIS
        Dynamic RDP Launcher with SRV Record Lookup and Console UI.

    .DESCRIPTION
        This function retrieves a list of named RDP targets from a remote JSON configuration file,
        performs SRV record lookups on custom records to resolve their FQDNs and ports, and presents
        a user-friendly selection interface via Out-ConsoleGridView. Upon selection, the function
        launches the Microsoft Remote Desktop client (mstsc.exe) to connect to the chosen host.

    .NOTES
        Author: Andrew Middleton
        Last Updated: 2025-05-11
        Requirements:
            - PowerShell 5.1 or later
            - ConsoleGuiTools (Microsoft.PowerShell.ConsoleGuiTools)
            - Internet access to retrieve JSON config
            - SRV records must be correctly configured in DNS
    #>

    Import-Module Microsoft.PowerShell.ConsoleGuiTools -ErrorAction Stop

    $baseDomain = "kleinert.io"
    $remoteUrl = "https://raw.githubusercontent.com/Oratorian/ubuntu-cleanup/main/rdpvars.json"

    try {
        $json = Invoke-RestMethod -Uri $remoteUrl -UseBasicParsing -ErrorAction Stop
        $serviceNames = @($json)
    } catch {
        Write-Error "Failed to fetch or parse service definitions from $remoteUrl. Error: $_"
        return
    }

    foreach ($svc in $serviceNames) {
        if (-not ($svc.ShortName -and $svc.DisplayName)) {
            Write-Error "Invalid service entry in JSON: $($svc | ConvertTo-Json -Compress)"
            return
        }
    }

    $rdpHosts = foreach ($svc in $serviceNames) {
        $srvName = "_rdp._$($svc.ShortName).$baseDomain"
        try {
            $srvRecords = Resolve-DnsName -Name $srvName -Type SRV -ErrorAction Stop
            $srvRecords = @($srvRecords) | Where-Object { $_.QueryType -eq 'SRV' }

            foreach ($record in $srvRecords) {
                $target = $record.NameTarget.TrimEnd('.')
                [PSCustomObject]@{
                    ShortName   = $svc.ShortName
                    DisplayName = "Connect to Server $($svc.DisplayName)"
                    Target      = $target
                    Port        = $record.Port
                }
            }
        } catch {
            Write-Warning "Failed to resolve $srvName : $_"
        }
    }

    if (-not $rdpHosts) {
        Write-Warning "No SRV entries could be resolved."
        return
    }

    $displayList = $rdpHosts | ForEach-Object {
        [PSCustomObject]@{ DisplayName = $_.DisplayName }
    }

    $selection = $displayList | Out-ConsoleGridView -Title "Select RDP Host to Connect" -OutputMode Single

    if ($selection) {
        $full = $rdpHosts | Where-Object { $_.DisplayName -eq $selection.DisplayName }

        $fqdn = $full.Target
        $port = $full.Port
        $rdpTarget = "$fqdn`:$port"

        Start-Process "mstsc.exe" -ArgumentList "/v:$rdpTarget"
    } else {
        Write-Host "No selection made. Exiting."
    }
}

Export-ModuleMember -Function Start-RDPLauncher