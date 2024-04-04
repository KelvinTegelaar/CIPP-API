function Add-CIPPApplicationPermission {
    [CmdletBinding()]
    param(
        $RequiredResourceAccess,
        $ApplicationId,
        $Tenantfilter
    )
    if ($ApplicationId -eq $ENV:ApplicationID -and $Tenantfilter -eq $env:TenantID) {
        return @('Cannot modify application permissions for CIPP-SAM on partner tenant')
    }
    Set-Location (Get-Item $PSScriptRoot).FullName
    if ($RequiredResourceAccess -eq 'CIPPDefaults') {
        $RequiredResourceAccess = (Get-Content '.\SAMManifest.json' | ConvertFrom-Json).requiredResourceAccess
    }
    $ServicePrincipalList = New-GraphGETRequest -uri "https://graph.microsoft.com/beta/servicePrincipals?`$select=AppId,id,displayName&`$top=999" -skipTokenCache $true -tenantid $Tenantfilter
    $ourSVCPrincipal = $ServicePrincipalList | Where-Object -Property AppId -EQ $ApplicationId
    if (!$ourSVCPrincipal) {
        #Our Service Principal isn't available yet. We do a sleep and reexecute after 3 seconds.
        Start-Sleep -Seconds 5
        $ServicePrincipalList = New-GraphGETRequest -uri "https://graph.microsoft.com/beta/servicePrincipals?`$select=AppId,id,displayName&`$top=999" -skipTokenCache $true -tenantid $Tenantfilter
        $ourSVCPrincipal = $ServicePrincipalList | Where-Object -Property AppId -EQ $ApplicationId
    }

    $Results = [System.Collections.ArrayList]@()

    $CurrentRoles = New-GraphGETRequest -uri "https://graph.microsoft.com/beta/servicePrincipals/$($ourSVCPrincipal.id)/appRoleAssignments" -tenantid $Tenantfilter -skipTokenCache $true

    $Grants = foreach ($App in $RequiredResourceAccess) {
        $svcPrincipalId = $ServicePrincipalList | Where-Object -Property AppId -EQ $App.resourceAppId
        if (!$svcPrincipalId) { continue }
        foreach ($SingleResource in $App.ResourceAccess | Where-Object -Property Type -EQ 'Role') {
            if ($SingleResource.id -In $CurrentRoles.appRoleId) { continue }
            [pscustomobject]@{
                principalId = $($ourSVCPrincipal.id)
                resourceId  = $($svcPrincipalId.id)
                appRoleId   = "$($SingleResource.Id)"
            }
        }
    }
    $counter = 0
    foreach ($Grant in $Grants) {
        try {
            $SettingsRequest = New-GraphPOSTRequest -body ($Grant | ConvertTo-Json) -uri "https://graph.microsoft.com/beta/servicePrincipals/$($ourSVCPrincipal.id)/appRoleAssignedTo" -tenantid $Tenantfilter -type POST
            $counter++
        } catch {
            $Results.add("Failed to grant $($Grant.appRoleId) to $($Grant.resourceId): $($_.Exception.Message)") | Out-Null
        }
    }
    "Added $counter Application permissions to $($ourSVCPrincipal.displayName)"
    return $Results
}