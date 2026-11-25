function Invoke-ExecDefenderMachineAction {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Security.Defender.ReadWrite
    .SYNOPSIS
        Isolate, release or antivirus scan a Defender device
    .DESCRIPTION
        Sends one Microsoft Defender for Endpoint response action to one device: Isolate (Full or Selective), Release from isolation, or an antivirus Scan (Quick or Full). The action runs with the CIPP application's permissions, so Defender shows the CIPP application as the requestor; the action comment starts with the technician who sent it. Returns 202 with Defender's action id and status. While another action of the same kind is still in progress on the device, Defender refuses the new one or returns the action already in progress; check ListDefenderMachineActions before sending it again.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers
    # One tenant: its default domain or tenant id.
    $TenantFilter = $Request.Body.tenantFilter
    # The device's Defender id (40 hexadecimal characters), as listed by ListDefenderMachines.
    $MachineId = $Request.Body.machineId
    # Isolate, Release or Scan.
    $Action = $Request.Body.Action
    # Isolate only. Full (default) cuts the device off the network except for Defender; Selective allows the limited connections Defender permits during selective isolation.
    $IsolationType = $Request.Body.IsolationType
    # Scan only. Quick (default) or Full.
    $ScanType = $Request.Body.ScanType
    # Optional note, added to the action in Defender after the technician's name.
    $Comment = $Request.Body.Comment

    if ($TenantFilter -isnot [string] -or [string]::IsNullOrWhiteSpace($TenantFilter) -or $TenantFilter -eq 'AllTenants' -or $TenantFilter -like 'group:*') {
        return ([HttpResponseContext]@{ StatusCode = [HttpStatusCode]::BadRequest; Body = @{ Results = 'tenantFilter must name one tenant.' } })
    }
    if ($MachineId -isnot [string] -or $MachineId -notmatch '\A[0-9a-fA-F]{40}\z') {
        return ([HttpResponseContext]@{ StatusCode = [HttpStatusCode]::BadRequest; Body = @{ Results = 'machineId must be a Defender device id (40 hexadecimal characters).' } })
    }
    if ($Action -isnot [string] -or $Action -cnotin 'Isolate', 'Release', 'Scan') {
        return ([HttpResponseContext]@{ StatusCode = [HttpStatusCode]::BadRequest; Body = @{ Results = 'Action must be Isolate, Release or Scan.' } })
    }
    if ($null -ne $IsolationType -and ($Action -cne 'Isolate' -or $IsolationType -isnot [string] -or $IsolationType -cnotin 'Full', 'Selective')) {
        return ([HttpResponseContext]@{ StatusCode = [HttpStatusCode]::BadRequest; Body = @{ Results = 'IsolationType applies only to Isolate and must be Full or Selective.' } })
    }
    if ($null -ne $ScanType -and ($Action -cne 'Scan' -or $ScanType -isnot [string] -or $ScanType -cnotin 'Quick', 'Full')) {
        return ([HttpResponseContext]@{ StatusCode = [HttpStatusCode]::BadRequest; Body = @{ Results = 'ScanType applies only to Scan and must be Quick or Full.' } })
    }
    if ($null -ne $Comment -and $Comment -isnot [string]) {
        return ([HttpResponseContext]@{ StatusCode = [HttpStatusCode]::BadRequest; Body = @{ Results = 'Comment must be text.' } })
    }

    $Technician = try { ([System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($Headers.'x-ms-client-principal')) | ConvertFrom-Json).userDetails } catch { $null }
    if (-not $Technician) { $Technician = $Headers.'x-ms-client-principal-name' }
    if (-not $Technician) { $Technician = 'CIPP' }

    $DefenderBody = @{ Comment = if ([string]::IsNullOrWhiteSpace($Comment)) { "$Technician via CIPP" } else { "$Technician via CIPP: $Comment" } }
    $Suffix, $Description = switch -CaseSensitive ($Action) {
        'Isolate' { $DefenderBody.IsolationType = $IsolationType ?? 'Full'; 'isolate', "$($DefenderBody.IsolationType) isolation" }
        'Release' { 'unisolate', 'Release from isolation' }
        'Scan' { $DefenderBody.ScanType = $ScanType ?? 'Quick'; 'runAntiVirusScan', "$($DefenderBody.ScanType) antivirus scan" }
    }

    try {
        $DefenderAction = New-GraphPOSTRequest -uri "https://api.securitycenter.microsoft.com/api/machines/$MachineId/$Suffix" -tenantid $TenantFilter -body ($DefenderBody | ConvertTo-Json -Compress) -scope 'https://api.securitycenter.microsoft.com/.default' -AsApp $true
        $Device = $DefenderAction.computerDnsName ?? $MachineId
        $Result = [PSCustomObject]@{
            resultText = "Sent $Description to Defender for $Device. Action id: $($DefenderAction.id). Status: $($DefenderAction.status)."
            state      = 'success'
            actionId   = $DefenderAction.id
            status     = $DefenderAction.status
        }
        Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message $Result.resultText -sev Info
        $StatusCode = [HttpStatusCode]::Accepted
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        $Result = "Failed to send $Description to Defender for device $($MachineId): $($ErrorMessage.NormalizedError) Check the device's action history before trying again."
        Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message $Result -sev Error -LogData $ErrorMessage
        $StatusCode = Get-CippErrorStatusCode -ErrorRecord $_
    }

    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = @{ Results = $Result }
        })
}
