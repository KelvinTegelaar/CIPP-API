function Get-CIPPAlertSpecificAppIds {
    <#
    .SYNOPSIS
        Alert when any of a chosen set of application ids is present in the tenant.
    .DESCRIPTION
        Looks up the service principals for the configured application ids and reports every one
        that exists in the tenant. Use it to watch for applications you want to know about the
        moment they appear, such as apps from a vendor that has announced a breach.
    .FUNCTIONALITY
        Entrypoint
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $false)]
        [Alias('input')]
        $InputValue,
        $TenantFilter
    )

    # The form posts either the bare input (a list of picked/typed ids or a string) or, for a
    # multi-input layout, an object carrying it under AppIds. Accept both.
    $RawAppIds = if ($InputValue -is [System.Collections.IDictionary]) {
        $InputValue['AppIds']
    } elseif ($null -ne $InputValue -and $InputValue -isnot [string] -and $InputValue.PSObject.Properties.Name -contains 'AppIds') {
        $InputValue.AppIds
    } else {
        $InputValue
    }
    $AppIds = [System.Collections.Generic.List[string]]::new()
    foreach ($Entry in @($RawAppIds)) {
        $Candidate = if ($Entry -is [string]) { $Entry } else { $Entry.value ?? $Entry.label }
        foreach ($Id in ([string]$Candidate -split '[,\s]+')) {
            $Trimmed = $Id.Trim()
            if ($Trimmed -match '^[0-9a-fA-F]{8}-([0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}$' -and $AppIds -notcontains $Trimmed.ToLower()) {
                $AppIds.Add($Trimmed.ToLower())
            }
        }
    }
    if ($AppIds.Count -eq 0) {
        Write-LogMessage -API 'Alerts' -tenant $TenantFilter -message 'Specific app ids alert: no valid application ids configured, nothing checked.' -sev Warning
        return
    }

    try {
        $Requests = for ($i = 0; $i -lt $AppIds.Count; $i += 15) {
            $Chunk = $AppIds[$i..([Math]::Min($i + 14, $AppIds.Count - 1))]
            @{
                id     = [string]$i
                method = 'GET'
                url    = "servicePrincipals?`$select=id,appId,displayName,accountEnabled,createdDateTime,appOwnerOrganizationId,publisherName&`$filter=appId in ('$($Chunk -join "','")')"
            }
        }
        $Responses = New-GraphBulkRequest -Requests @($Requests) -tenantid $TenantFilter
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'Alerts' -tenant $TenantFilter -message "Specific app ids alert: unable to look up service principals: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        return
    }

    $AlertData = [System.Collections.Generic.List[PSCustomObject]]::new()
    foreach ($Response in @($Responses)) {
        foreach ($ServicePrincipal in @($Response.body.value)) {
            if (-not $ServicePrincipal.appId) { continue }
            $Message = "Application '{0}' ({1}) is present in the tenant." -f $ServicePrincipal.displayName, $ServicePrincipal.appId
            $Finding = [PSCustomObject]@{
                Message            = $Message
                AppName            = $ServicePrincipal.displayName
                AppId              = $ServicePrincipal.appId
                ServicePrincipalId = $ServicePrincipal.id
                Publisher          = $ServicePrincipal.publisherName
                AppOwnerTenantId   = $ServicePrincipal.appOwnerOrganizationId
                Enabled            = $ServicePrincipal.accountEnabled
                Created            = $ServicePrincipal.createdDateTime
                Tenant             = $TenantFilter
            }
            $AlertData.Add($Finding)
        }
    }

    Write-AlertTrace -cmdletName $MyInvocation.MyCommand -tenantFilter $TenantFilter -data $AlertData
}
